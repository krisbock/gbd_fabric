#!/usr/bin/env python3
"""Generate sample healthcare CSVs for the Fabric Git-deployment demo.

The HospitalETL notebook generates its own synthetic data inside Spark (scaled by
the RowMultiplier variable), so these CSVs are optional. They exist so the dataset
is visible/reviewable in the repo and can be uploaded to a lakehouse Files area if
you prefer a file-based load.

Usage:
    python data/generate_data.py --rows 500 --out data/generated
"""
from __future__ import annotations

import argparse
import csv
import datetime
import os
import random

DEPARTMENTS = [
    (1, "Emergency"), (2, "Cardiology"), (3, "Orthopedics"),
    (4, "Pediatrics"), (5, "Oncology"), (6, "General Medicine"),
]
DIAGNOSES = [
    (1, "Acute MI", "Cardiac"), (2, "Pneumonia", "Respiratory"),
    (3, "Fracture", "Musculoskeletal"), (4, "Sepsis", "Infectious"),
    (5, "Diabetes", "Endocrine"), (6, "Stroke", "Neurological"),
    (7, "Appendicitis", "Digestive"), (8, "Asthma", "Respiratory"),
]
FIRST_NAMES = ["Alex", "Sam", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Jamie", "Avery", "Quinn"]
LAST_NAMES = ["Smith", "Patel", "Nguyen", "Garcia", "Khan", "OBrien", "Rossi", "Cohen", "Mueller", "Tanaka"]


def write_csv(path: str, header: list[str], rows: list[tuple]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(header)
        writer.writerows(rows)
    print(f"  wrote {os.path.basename(path)} ({len(rows)} rows)")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate sample healthcare CSVs.")
    parser.add_argument("--rows", type=int, default=500, help="Number of fact_encounter rows.")
    parser.add_argument("--days", type=int, default=30, help="Days of dim_date history.")
    parser.add_argument("--out", default="data/generated", help="Output directory.")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for reproducibility.")
    args = parser.parse_args()

    random.seed(args.seed)
    os.makedirs(args.out, exist_ok=True)

    today = datetime.date.today()
    start = today - datetime.timedelta(days=args.days)

    # dim_date
    date_rows = []
    d = start
    while d <= today:
        date_rows.append((
            int(d.strftime("%Y%m%d")), d.isoformat(), d.year, d.month,
            d.strftime("%B"), d.day, d.strftime("%A"), d.weekday() >= 5,
        ))
        d += datetime.timedelta(days=1)
    write_csv(os.path.join(args.out, "dim_date.csv"),
              ["DateKey", "Date", "Year", "Month", "MonthName", "Day", "DayOfWeek", "IsWeekend"],
              date_rows)

    # dim_department
    write_csv(os.path.join(args.out, "dim_department.csv"),
              ["DepartmentKey", "DepartmentName"], DEPARTMENTS)

    # dim_diagnosis
    write_csv(os.path.join(args.out, "dim_diagnosis.csv"),
              ["DiagnosisKey", "DiagnosisName", "DiagnosisCategory"], DIAGNOSES)

    # dim_provider
    provider_rows = [
        (i, f"Dr. {random.choice(LAST_NAMES)}", random.choice(DEPARTMENTS)[0])
        for i in range(1, 11)
    ]
    write_csv(os.path.join(args.out, "dim_provider.csv"),
              ["ProviderKey", "ProviderName", "DepartmentKey"], provider_rows)

    # dim_patient
    num_patients = max(args.rows // 2, 50)
    patient_rows = [
        (i, f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}",
         random.choice(["F", "M", "X"]),
         random.choice(["0-17", "18-34", "35-49", "50-64", "65+"]))
        for i in range(1, num_patients + 1)
    ]
    write_csv(os.path.join(args.out, "dim_patient.csv"),
              ["PatientKey", "PatientName", "Gender", "AgeGroup"], patient_rows)

    # fact_encounter
    date_keys = [r[0] for r in date_rows]
    fact_rows = []
    for i in range(1, args.rows + 1):
        fact_rows.append((
            i, random.choice(date_keys), random.randint(1, num_patients),
            random.randint(1, 10), random.choice(DEPARTMENTS)[0],
            random.choice(DIAGNOSES)[0], random.randint(1, 12),
            random.random() < 0.12, round(random.uniform(500, 50000), 2),
        ))
    write_csv(os.path.join(args.out, "fact_encounter.csv"),
              ["EncounterKey", "DateKey", "PatientKey", "ProviderKey", "DepartmentKey",
               "DiagnosisKey", "LengthOfStayDays", "IsReadmission", "TotalCharges"],
              fact_rows)

    print(f"\nDone. CSVs written to '{args.out}'.")


if __name__ == "__main__":
    main()
