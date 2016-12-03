--
-- Create a new column in `SmtpOutboxTable` to mark that the user required the
-- delivery status notification for that message.
--

ALTER TABLE SmtpOutboxTable ADD COLUMN request_dsn BOOLEAN DEFAULT false;
