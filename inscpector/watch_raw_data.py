import subprocess
import sys
import threading
import time
from pathlib import Path

from watchdog.events import FileSystemEventHandler
from watchdog.observers.polling import PollingObserver

BASE_DIR = Path(__file__).parent.resolve()
DRIVE_DIR = (
    Path.home()
    / "Library/CloudStorage/GoogleDrive-ait.kajilab@gmail.com"
    / "マイドライブ/2026/sana/かくれんぼ/wifi_measurements"
)
RAW_DATA_DIR = DRIVE_DIR / "raw_data"
OUTPUT_DIR = DRIVE_DIR / "jaccard_result"

# raw_dataの同期が終わるまで少し待ってからまとめて1回実行するためのデバウンス秒数
DEBOUNCE_SECONDS = 10.0


def run_jaccard() -> None:
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] raw_dataの変化を検知、jaccard.pyを実行します", flush=True)
    result = subprocess.run(
        [sys.executable, str(BASE_DIR / "jaccard.py"), str(RAW_DATA_DIR), "-o", str(OUTPUT_DIR)],
        capture_output=True,
        text=True,
    )
    print(result.stdout, end="", flush=True)
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr, flush=True)


class DebouncedRunner(FileSystemEventHandler):
    def __init__(self) -> None:
        self._timer: threading.Timer | None = None
        self._lock = threading.Lock()

    def _schedule(self) -> None:
        with self._lock:
            if self._timer is not None:
                self._timer.cancel()
            self._timer = threading.Timer(DEBOUNCE_SECONDS, run_jaccard)
            self._timer.daemon = True
            self._timer.start()

    def on_created(self, event) -> None:
        if not event.is_directory:
            self._schedule()

    def on_modified(self, event) -> None:
        if not event.is_directory:
            self._schedule()


def main() -> None:
    RAW_DATA_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    handler = DebouncedRunner()
    # Googleドライブデスクトップの同期フォルダはFSEventsを発行しないことがあるため
    # ポーリング方式で確実に変化を検知する
    observer = PollingObserver(timeout=10)
    observer.schedule(handler, str(RAW_DATA_DIR), recursive=True)
    observer.start()
    print(f"監視開始: {RAW_DATA_DIR}", flush=True)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()


if __name__ == "__main__":
    main()
