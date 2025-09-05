from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.email import EmailOperator
from datetime import datetime, timedelta
import boto3
import os

AWS_REGION = os.getenv("AWS_DEFAULT_REGION", "us-east-1")
RDS_INSTANCE_ID = "your-rds-instance-id"
SNAPSHOT_PREFIX = "daily-snapshot"
EXPORT_BUCKET = "your-s3-bucket-name"
EMAIL_RECIPIENT = "you@example.com"


def create_snapshot():
    rds = boto3.client("rds", region_name=AWS_REGION)
    snapshot_id = f"{SNAPSHOT_PREFIX}-{datetime.utcnow().strftime('%Y-%m-%d-%H-%M')}"
    rds.create_db_snapshot(
        DBInstanceIdentifier=RDS_INSTANCE_ID,
        DBSnapshotIdentifier=snapshot_id
    )
    return snapshot_id


def export_snapshot_to_s3(snapshot_id: str):
    rds = boto3.client("rds", region_name=AWS_REGION)
    export_task_id = f"export-{snapshot_id}"
    rds.start_export_task(
        ExportTaskIdentifier=export_task_id,
        SourceArn=f"arn:aws:rds:{AWS_REGION}:YOUR_AWS_ACCOUNT:db:{RDS_INSTANCE_ID}",
        S3BucketName=EXPORT_BUCKET,
        IamRoleArn="arn:aws:iam::YOUR_AWS_ACCOUNT:role/YourRDSExportRole",
        KmsKeyId="YOUR_KMS_KEY_ARN",
        SnapshotTime=datetime.utcnow()
    )
    return export_task_id


default_args = {
    "owner": "airflow",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    "rds_snapshot_to_s3",
    default_args=default_args,
    description="Daily RDS snapshot to S3",
    schedule_interval="@daily",
    start_date=datetime(2025, 9, 5),
    catchup=False,
    tags=["rds", "s3"],
) as dag:

    snapshot_task = PythonOperator(
        task_id="create_snapshot",
        python_callable=create_snapshot
    )

    export_task = PythonOperator(
        task_id="export_to_s3",
        python_callable=lambda **kwargs: export_snapshot_to_s3(
            kwargs["ti"].xcom_pull(task_ids="create_snapshot")),
        provide_context=True
    )

    email_snapshot_success = EmailOperator(
        task_id="snapshot_success_email",
        to=EMAIL_RECIPIENT,
        subject="RDS Snapshot Created Successfully",
        html_content="""<h3>The RDS snapshot has been created successfully.</h3>
                        <p>Snapshot ID: {{ ti.xcom_pull(task_ids='create_snapshot') }}</p>"""
    )

    email_export_success = EmailOperator(
        task_id="export_success_email",
        to=EMAIL_RECIPIENT,
        subject="RDS Snapshot Export Started Successfully",
        html_content="""<h3>The RDS snapshot export has been started successfully.</h3>
                        <p>Export Task ID: {{ ti.xcom_pull(task_ids='export_to_s3') }}</p>"""
    )

    snapshot_task >> email_snapshot_success >> export_task >> email_export_success
