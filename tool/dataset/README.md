# Dataset builder

`build_dataset.py` builds the card catalog and ORB references used for card recognition, validates them, and publishes
the dataset to `assets/data/`.

Run from the project root with Python 3.10 or newer:

```powershell
python -m pip install -r tool/dataset/requirements.txt
python tool/dataset/build_dataset.py
```

Use `python tool/dataset/build_dataset.py --help` for options.

### AI usage

The Python scripts in this directory were created with AI assistance for the scope of this project.
