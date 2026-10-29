"""Video input: USB webcam, the Mac's built-in camera, HDMI capture dongle, Pi camera,
a 360 camera (Insta360 X4 in USB webcam mode), or a file.

On Linux capture runs on a background thread. On macOS it runs in a separate
process (open_video picks): the macOS OpenCV wheels bundle their own SDL, which
clashes with pygame's in one process, and macOS camera permission has to be
requested from a main thread.

Frames are kept in BGR (OpenCV's native order, and also what picamera2's
"RGB888" actually delivers); the shaders swizzle with .bgr, so no CPU colour
conversion is needed. Unplugging/replugging the source is handled by retrying.
"""

import glob
import multiprocessing as mp
import os
import sys
import threading
import time
from multiprocessing import shared_memory

import numpy as np

# Sources that deliver a 2:1 equirectangular 360 panorama
CAMERAS_360 = ("insta360", "insta", "x4", "x3", "theta")


def is_360(source):
    return str(source).lower() in CAMERAS_360


def frame_size(source, size):
    # 360 panoramas keep their 2:1 shape; 1024x512 is plenty at projector render scale
    return (1024, 512) if is_360(source) else tuple(size)


def open_video(source, size=(640, 360), capture_size=None):
    if sys.platform == "darwin":
        return ProcessVideoInput(source, size, capture_size)
    return VideoInput(source, size, capture_size)


def find_v4l2_device(name_fragment):
    """Linux: first /dev/videoN whose driver name contains name_fragment (e.g. 'Insta360')."""
    for node in sorted(glob.glob("/sys/class/video4linux/video*"), key=lambda p: int(p.rsplit("video", 1)[1])):
        try:
            with open(os.path.join(node, "name")) as f:
                name = f.read().strip()
            with open(os.path.join(node, "index")) as f:
                index = int(f.read().strip() or 0)
        except OSError:
            continue
        if name_fragment.lower() in name.lower() and index == 0:  # index 0 = the capture node, not metadata
            return "/dev/" + os.path.basename(node), name
    return None, None


class VideoInput(threading.Thread):
    def __init__(self, source, size=(640, 360), capture_size=None):
        super().__init__(daemon=True)
        self.source = source
        self.is_360 = is_360(source)
        self.size = frame_size(source, size)
        self.capture_size = tuple(capture_size) if capture_size else ((1920, 960) if self.is_360 else (1280, 720))
        self.active = True
        self.status = "starting"
        self._frame = None
        self._frame_id = 0
        self._lock = threading.Lock()
        self._stop = threading.Event()

    def latest(self):
        with self._lock:
            return self._frame_id, self._frame

    def toggle(self):
        self.active = not self.active

    def stop(self):
        self._stop.set()

    def _publish(self, frame):
        with self._lock:
            self._frame = frame
            self._frame_id += 1

    def run(self):
        last_error = None
        while not self._stop.is_set():
            try:
                if str(self.source).lower() in ("picam", "picamera", "csi"):
                    self._run_picamera()
                else:
                    self._run_opencv()
            except Exception as e:
                self.status = f"error: {e}"
                if str(e) != last_error:  # don't spam the log while the camera is unplugged
                    print(f"[video] {e}; retrying every 3s")
                last_error = str(e)
            self._stop.wait(3.0)

    def _run_picamera(self):
        from picamera2 import Picamera2

        cam = Picamera2()
        cam.configure(cam.create_video_configuration(main={"size": self.size, "format": "RGB888"}))
        cam.start()
        self.status = "live (picamera)"
        print("[video] Pi camera started")
        try:
            while not self._stop.is_set():
                self._publish(cam.capture_array())
        finally:
            cam.stop()
            cam.close()

    def _run_opencv(self):
        import cv2

        src = self.source
        if self.is_360:
            dev, name = find_v4l2_device("insta")
            if dev is None and os.path.exists("/sys/class/video4linux"):
                raise RuntimeError("no Insta360 found: plug it in over USB and choose 'Webcam Mode' on the camera")
            src = dev or 0  # non-Linux: assume it's the first camera
            if name:
                print(f"[video] found {name} at {dev}")
        is_file = isinstance(src, str) and not src.isdigit() and not src.startswith("/dev/") and os.path.exists(src)
        if isinstance(src, str) and src.isdigit():
            src = int(src)

        is_v4l2 = not is_file and os.path.exists("/sys/class/video4linux")
        if is_v4l2:
            cap = cv2.VideoCapture(src, cv2.CAP_V4L2)
            cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))  # much cheaper over USB
        else:
            cap = cv2.VideoCapture(src)
        if not is_file:
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.capture_size[0])
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.capture_size[1])
            cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)  # always the freshest frame, lowest latency
        if not cap.isOpened():
            raise RuntimeError(f"cannot open video source {self.source!r}")
        got = (int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)))
        print(f"[video] capturing at {got[0]}x{got[1]}")
        if self.is_360 and got[1] and abs(got[0] / got[1] - 2.0) > 0.05:
            print("[video] warning: expected a 2:1 panorama from the 360 camera; is it in Webcam Mode?")

        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        frame_time = 1.0 / fps if is_file else 0.0
        self.status = f"live ({self.source})"
        print(f"[video] opened {self.source!r}")
        try:
            while not self._stop.is_set():
                t0 = time.monotonic()
                ok, frame = cap.read()
                if not ok:
                    if is_file:
                        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)  # loop clips
                        continue
                    raise RuntimeError("video source stopped delivering frames")
                if (frame.shape[1], frame.shape[0]) != self.size:
                    frame = cv2.resize(frame, self.size, interpolation=cv2.INTER_LINEAR)
                self._publish(frame)
                if frame_time:
                    time.sleep(max(0.0, frame_time - (time.monotonic() - t0)))
        finally:
            cap.release()


class _ChildVideoInput(VideoInput):
    """VideoInput running inside the capture process; reports status through shared memory."""

    def __init__(self, status_buf, *args):
        self._status_buf = status_buf
        super().__init__(*args)

    @property
    def status(self):
        return self._status_buf.value.decode(errors="replace")

    @status.setter
    def status(self, text):
        self._status_buf.value = text.encode()[:255]


def _capture_process(source, size, capture_size, shm_name, seq, stop_event, status_buf):
    shm = shared_memory.SharedMemory(name=shm_name)
    w, h = size
    buf = np.ndarray((h, w, 3), dtype=np.uint8, buffer=shm.buf)
    worker = _ChildVideoInput(status_buf, source, size, capture_size)
    worker._stop = stop_event

    def publish(frame):
        seq.value += 1          # odd = write in progress
        buf[:] = frame
        seq.value += 1          # even = frame complete

    worker._publish = publish
    try:
        worker.run()            # on this process's main thread, so macOS can ask for camera access
    except KeyboardInterrupt:
        pass
    finally:
        del buf
        shm.close()


class ProcessVideoInput:
    """Same interface as VideoInput, but capture happens in a child process (macOS)."""

    def __init__(self, source, size=(640, 360), capture_size=None):
        self.source = source
        self.is_360 = is_360(source)
        self.size = frame_size(source, size)
        self.active = True
        w, h = self.size
        ctx = mp.get_context("spawn")
        self._shm = shared_memory.SharedMemory(create=True, size=w * h * 3)
        self._buf = np.ndarray((h, w, 3), dtype=np.uint8, buffer=self._shm.buf)
        self._seq = ctx.Value("Q", 0, lock=False)
        self._stop = ctx.Event()
        self._status = ctx.Array("c", 256, lock=False)
        self._status.value = b"starting"
        self._proc = ctx.Process(target=_capture_process, daemon=True,
                                 args=(source, self.size, capture_size, self._shm.name,
                                       self._seq, self._stop, self._status))
        self._last_seq = 0
        self._frame = None
        self._frame_id = 0

    @property
    def status(self):
        return self._status.value.decode(errors="replace")

    def start(self):
        self._proc.start()

    def latest(self):
        s = self._seq.value
        if s and s % 2 == 0 and s != self._last_seq:
            frame = self._buf.copy()
            if self._seq.value == s:  # not overwritten while copying
                self._frame, self._last_seq = frame, s
                self._frame_id += 1
        return self._frame_id, self._frame

    def toggle(self):
        self.active = not self.active

    def stop(self):
        self._stop.set()
        self._proc.join(timeout=2.0)
        if self._proc.is_alive():
            self._proc.terminate()
        self._buf = None
        self._shm.close()
        try:
            self._shm.unlink()
        except FileNotFoundError:
            pass
