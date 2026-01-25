from pathlib import Path
import logging


def setup_logging() -> None:
    logs_dir = Path.cwd() / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    log_file = logs_dir / "app.log"

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        handlers=[logging.FileHandler(log_file, encoding="utf-8"), logging.StreamHandler()],
    )


def main() -> None:
    setup_logging()
    logging.getLogger(__name__).info("{{REPO_NAME}}: ok")
    print("{{REPO_NAME}}: ok")


if __name__ == "__main__":
    main()