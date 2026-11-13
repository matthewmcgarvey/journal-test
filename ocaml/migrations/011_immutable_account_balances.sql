CREATE TRIGGER account_balances_are_immutable
BEFORE UPDATE OR DELETE ON account_balances
FOR EACH ROW EXECUTE FUNCTION reject_record_mutation();
