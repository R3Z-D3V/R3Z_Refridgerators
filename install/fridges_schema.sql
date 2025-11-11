-- One-time SQL schema for the fridge resource (manual import)
-- Run this in your MySQL console or import via phpMyAdmin

CREATE TABLE IF NOT EXISTS `fridges` (
  `id` VARCHAR(64) NOT NULL,
  `name` VARCHAR(64) DEFAULT NULL,
  `coords_x` DOUBLE DEFAULT 0,
  `coords_y` DOUBLE DEFAULT 0,
  `coords_z` DOUBLE DEFAULT 0,
  `data` LONGTEXT NOT NULL,
  `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Example: to insert a fridge with empty data
-- INSERT INTO `fridges` (`id`, `name`, `coords_x`, `coords_y`, `coords_z`, `data`) VALUES ('fridge_1', 'Default Fridge', 0, 0, 0, '{}');
