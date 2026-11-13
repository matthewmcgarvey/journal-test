CREATE TRIGGER accounts_are_immutable
BEFORE UPDATE OR DELETE ON accounts
FOR EACH ROW EXECUTE FUNCTION reject_record_mutation();
