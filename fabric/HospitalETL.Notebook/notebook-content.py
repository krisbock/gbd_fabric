# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {}
# META }

# MARKDOWN ********************

# ### HospitalETL
# Generates a small hospital-operations star schema into the **Healthcare** lakehouse.
# # This notebook is **environment-aware** and **portable**:
# * It reads the **EnvConfig** variable library for `EnvironmentName`, `RowMultiplier`
#   and `RefreshWindowDays` (different per workspace via the active value set).
# * It resolves the **Healthcare** lakehouse **by name** in whatever workspace it runs in,
#   so the same definition works in Feature / Dev / Test / Prod with no rebinding.
# * It writes an `env_banner` Delta table whose contents prove which environment ran the load.

# CELL ********************

# Read environment configuration from the EnvConfig variable library (with safe fallbacks).
env_name = "Development"
row_multiplier = 1
refresh_window_days = 30

try:
    from notebookutils import variableLibrary
    vl = variableLibrary.getLibrary("EnvConfig")
    env_name = str(vl.EnvironmentName)
    row_multiplier = int(str(vl.RowMultiplier))
    refresh_window_days = int(str(vl.RefreshWindowDays))
    print("Loaded values from variable library 'EnvConfig'.")
except Exception as ex:  # noqa: BLE001
    print(f"Variable library not available, using defaults. Reason: {ex}")

print(f"EnvironmentName     = {env_name}")
print(f"RowMultiplier       = {row_multiplier}")
print(f"RefreshWindowDays   = {refresh_window_days}")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# Resolve the Healthcare lakehouse BY NAME in the current workspace, then derive the Tables path.
import notebookutils

lh = notebookutils.lakehouse.get("Healthcare")
abfs_path = lh["properties"]["abfsPath"]
tables_path = f"{abfs_path}/Tables"
print(f"Writing Delta tables to: {tables_path}")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# Deterministic synthetic generator (seeded) so loads are reproducible per environment.
import random
import datetime
from pyspark.sql import Row

random.seed(42)

today = datetime.date.today()
start_date = today - datetime.timedelta(days=refresh_window_days)

# Reference data
departments = [
    (1, "Emergency"), (2, "Cardiology"), (3, "Orthopedics"),
    (4, "Pediatrics"), (5, "Oncology"), (6, "General Medicine"),
]
diagnoses = [
    (1, "Acute MI", "Cardiac"), (2, "Pneumonia", "Respiratory"),
    (3, "Fracture", "Musculoskeletal"), (4, "Sepsis", "Infectious"),
    (5, "Diabetes", "Endocrine"), (6, "Stroke", "Neurological"),
    (7, "Appendicitis", "Digestive"), (8, "Asthma", "Respiratory"),
]
first_names = ["Alex", "Sam", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Jamie", "Avery", "Quinn"]
last_names = ["Smith", "Patel", "Nguyen", "Garcia", "Khan", "OBrien", "Rossi", "Cohen", "Mueller", "Tanaka"]

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# dim_date
date_rows = []
d = start_date
while d <= today:
    date_rows.append(Row(
        DateKey=int(d.strftime("%Y%m%d")),
        Date=d.isoformat(),
        Year=d.year,
        Month=d.month,
        MonthName=d.strftime("%B"),
        Day=d.day,
        DayOfWeek=d.strftime("%A"),
        IsWeekend=d.weekday() >= 5,
    ))
    d += datetime.timedelta(days=1)
dim_date = spark.createDataFrame(date_rows)

# dim_department
dim_department = spark.createDataFrame(
    [Row(DepartmentKey=k, DepartmentName=n) for k, n in departments]
)

# dim_diagnosis
dim_diagnosis = spark.createDataFrame(
    [Row(DiagnosisKey=k, DiagnosisName=n, DiagnosisCategory=c) for k, n, c in diagnoses]
)

# dim_provider (scaled lightly by multiplier)
num_providers = 10 * row_multiplier
dim_provider = spark.createDataFrame([
    Row(
        ProviderKey=i,
        ProviderName=f"Dr. {random.choice(last_names)}",
        DepartmentKey=random.choice(departments)[0],
    )
    for i in range(1, num_providers + 1)
])

# dim_patient (scaled by multiplier)
num_patients = 200 * row_multiplier
dim_patient = spark.createDataFrame([
    Row(
        PatientKey=i,
        PatientName=f"{random.choice(first_names)} {random.choice(last_names)}",
        Gender=random.choice(["F", "M", "X"]),
        AgeGroup=random.choice(["0-17", "18-34", "35-49", "50-64", "65+"]),
    )
    for i in range(1, num_patients + 1)
])

print(f"dim_date={dim_date.count()}  dim_provider={num_providers}  dim_patient={num_patients}")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# fact_encounter (scaled by multiplier and the refresh window)
num_encounters = 500 * row_multiplier
date_keys = [r.DateKey for r in dim_date.select("DateKey").collect()]

fact_rows = []
for i in range(1, num_encounters + 1):
    admit = random.choice(date_keys)
    los = random.randint(1, 12)               # length of stay (days)
    readmitted = random.random() < 0.12       # ~12% readmission
    fact_rows.append(Row(
        EncounterKey=i,
        DateKey=admit,
        PatientKey=random.randint(1, num_patients),
        ProviderKey=random.randint(1, num_providers),
        DepartmentKey=random.choice(departments)[0],
        DiagnosisKey=random.choice(diagnoses)[0],
        LengthOfStayDays=los,
        IsReadmission=readmitted,
        TotalCharges=round(random.uniform(500, 50000), 2),
    ))
fact_encounter = spark.createDataFrame(fact_rows)
print(f"fact_encounter={num_encounters}")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# Write all dimension and fact tables as managed Delta tables under /Tables.
def write_delta(df, name):
    df.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save(f"{tables_path}/{name}")
    print(f"  wrote {name}")

write_delta(dim_date, "dim_date")
write_delta(dim_department, "dim_department")
write_delta(dim_diagnosis, "dim_diagnosis")
write_delta(dim_provider, "dim_provider")
write_delta(dim_patient, "dim_patient")
write_delta(fact_encounter, "fact_encounter")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

# env_banner — single-row proof table that reflects the active value set for this workspace.
load_ts = datetime.datetime.utcnow().isoformat()
readmissions = fact_encounter.filter("IsReadmission = true").count()
readmission_rate = round(100.0 * readmissions / max(num_encounters, 1), 1)

env_banner = spark.createDataFrame([Row(
    EnvironmentName=env_name,
    RowMultiplier=row_multiplier,
    RefreshWindowDays=refresh_window_days,
    EncounterCount=num_encounters,
    PatientCount=num_patients,
    ReadmissionRatePct=readmission_rate,
    LoadTimestampUtc=load_ts,
)])
write_delta(env_banner, "env_banner")

print("\n=== Load complete ===")
env_banner.show(truncate=False)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
