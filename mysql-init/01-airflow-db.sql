-- Creates the Airflow metadata database and grants the app user access.
-- Runs once on first container start (MySQL skips this dir on subsequent starts).
CREATE DATABASE IF NOT EXISTS airflow_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON airflow_db.* TO 'openmetadata'@'%';
FLUSH PRIVILEGES;
