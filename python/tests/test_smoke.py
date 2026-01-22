import importlib


def test_smoke() -> None:
    pkg = importlib.import_module("{{PY_PACKAGE}}")
    assert hasattr(pkg, "__version__")

    main_mod = importlib.import_module("{{PY_PACKAGE}}.__main__")
    main_mod.main()
