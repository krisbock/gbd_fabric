# Sample data

The `HospitalETL` notebook generates its own synthetic star schema inside Spark,
**scaled by the `RowMultiplier` variable** from the `EnvConfig` variable library
(Dev = 1×, Test = 5×, Prod = 20×). So you normally do **not** need to load any files.

`generate_data.py` is provided only so the dataset is reviewable in the repo and can
be uploaded to a lakehouse `Files` area if you prefer a file-based load.

```bash
python data/generate_data.py --rows 500 --days 30 --out data/generated
```

Tables produced:

| Table | Grain |
| --- | --- |
| `dim_date` | one row per calendar day |
| `dim_department` | hospital department |
| `dim_diagnosis` | diagnosis + category |
| `dim_provider` | clinician |
| `dim_patient` | patient |
| `fact_encounter` | one row per hospital encounter |

Generated CSVs land in `data/generated/` which is git-ignored.
