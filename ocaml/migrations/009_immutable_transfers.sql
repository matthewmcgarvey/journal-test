CREATE TRIGGER transfers_are_immutable
BEFORE UPDATE OR DELETE ON transfers
FOR EACH ROW EXECUTE FUNCTION reject_record_mutation();
