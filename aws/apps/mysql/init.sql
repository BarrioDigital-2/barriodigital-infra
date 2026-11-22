-- Se ejecuta UNA sola vez, cuando MySQL arranca con el volumen vacío.
-- La imagen oficial crea el usuario barriodigital con permisos solo sobre MYSQL_DATABASE (barriodigital);
-- aquí se crean las bases propias de catalog y report y se le dan permisos sobre ellas.
CREATE DATABASE IF NOT EXISTS barriodigital_catalog;
CREATE DATABASE IF NOT EXISTS barriodigital_report;

GRANT ALL PRIVILEGES ON barriodigital_catalog.* TO 'barriodigital'@'%';
GRANT ALL PRIVILEGES ON barriodigital_report.* TO 'barriodigital'@'%';
FLUSH PRIVILEGES;
