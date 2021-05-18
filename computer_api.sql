SET NAMES utf8;
SET time_zone = '+00:00';
SET foreign_key_checks = 0;
SET sql_mode = 'NO_AUTO_VALUE_ON_ZERO';

CREATE DATABASE computer_api CHARACTER SET utf8 COLLATE utf8_unicode_ci;

USE computer_api;

DROP TABLE IF EXISTS `tbl_error`;
CREATE TABLE `tbl_error` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `error_text` varchar(1000) COLLATE utf8_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;


DROP TABLE IF EXISTS `tbl_users`;
CREATE TABLE `tbl_users` (
  `user_id` int(11) NOT NULL AUTO_INCREMENT,
  `user_email` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL,
  `user_hash` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL,
  `user_salt` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL,
  `user_name` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL,
  `user_location` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL,
  `user_image_file` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL,
  `user_token` varchar(40) COLLATE utf8_unicode_ci DEFAULT NULL,
  `user_api_key` varchar(40) COLLATE utf8_unicode_ci DEFAULT NULL,
  `user_activation_code` varchar(40) COLLATE utf8_unicode_ci DEFAULT NULL,
  `user_activation_flag` varchar(1) COLLATE utf8_unicode_ci DEFAULT NULL,
  `user_activated_at` datetime DEFAULT NULL,
  `user_last_login_at` datetime DEFAULT NULL,
  `user_login_count` int(11) DEFAULT '0',
  `user_active` int(11) DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `modified_at` datetime DEFAULT NULL,
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;


DROP TABLE IF EXISTS `tbl_users_log`;
CREATE TABLE `tbl_users_log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `log_view` varchar(30) COLLATE utf8_unicode_ci DEFAULT NULL,
  `log_type` varchar(30) COLLATE utf8_unicode_ci DEFAULT NULL,
  `log_text` varchar(1000) COLLATE utf8_unicode_ci DEFAULT NULL,
  `log_user` int(11) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;


CREATE EVENT clear_user_token_every_hour
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
ENDS CURRENT_TIMESTAMP + INTERVAL 12 MONTH
ON COMPLETION PRESERVE
DO
   Update tbl_users SET user_token = Null
   WHERE user_last_login_at < NOW() - INTERVAL 1 HOUR;

SHOW PROCESSLIST;
SET GLOBAL event_scheduler = ON;
SHOW EVENTS FROM computer_api;
