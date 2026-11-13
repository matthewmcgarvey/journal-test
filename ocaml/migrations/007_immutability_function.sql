CREATE FUNCTION reject_record_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'journal records are immutable'
    USING ERRCODE = '55000';
END;
$$;
