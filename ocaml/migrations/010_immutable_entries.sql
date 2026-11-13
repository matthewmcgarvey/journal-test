CREATE TRIGGER entries_are_immutable
BEFORE UPDATE OR DELETE ON entries
FOR EACH ROW EXECUTE FUNCTION reject_record_mutation();
