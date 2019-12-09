DROP TABLE IF EXISTS `users`;
CREATE TABLE `users` (
  `id` varchar(255) NOT NULL DEFAULT '',
  `nick` varchar(255) NOT NULL DEFAULT '',
  `admin` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) CHARSET=utf8;

DROP TABLE IF EXISTS `settings`;
CREATE TABLE `settings` (
  `id` varchar(255) NOT NULL DEFAULT '',
  `short` varchar(255) NOT NULL DEFAULT '',
  `bool` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) CHARSET=utf8;
INSERT INTO `settings` SET id='hostname', short='CONFIG_ME_APPHOSTNAME' ON DUPLICATE KEY UPDATE short='CONFIG_ME_APPHOSTNAME';
