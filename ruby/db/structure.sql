SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: prevent_immutable_record_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_immutable_record_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION '% records are immutable', TG_TABLE_NAME
    USING ERRCODE = '55000';
END;
$$;


--
-- Name: require_tracked_account_for_balance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.require_tracked_account_for_balance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM accounts WHERE id = NEW.account_id AND track_balance
  ) THEN
    RAISE EXCEPTION 'Cannot record a balance for an untracked account'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account_balances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_balances (
    id integer NOT NULL,
    account_id integer NOT NULL,
    running_balance integer NOT NULL,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
ALTER TABLE ONLY public.account_balances ALTER COLUMN id SET (pg_attver=31763464);
ALTER TABLE ONLY public.account_balances ALTER COLUMN account_id SET (pg_attver=31763464);
ALTER TABLE ONLY public.account_balances ALTER COLUMN running_balance SET (pg_attver=31763464);
ALTER TABLE ONLY public.account_balances ALTER COLUMN created_at SET (pg_attver=31763464);


--
-- Name: account_balances_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.account_balances_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: account_balances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.account_balances_id_seq OWNED BY public.account_balances.id;


--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id integer NOT NULL,
    external_id character varying NOT NULL,
    track_balance boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);
ALTER TABLE ONLY public.accounts ALTER COLUMN id SET (pg_attver=31672920);
ALTER TABLE ONLY public.accounts ALTER COLUMN external_id SET (pg_attver=31672920);
ALTER TABLE ONLY public.accounts ALTER COLUMN track_balance SET (pg_attver=31672920);
ALTER TABLE ONLY public.accounts ALTER COLUMN created_at SET (pg_attver=31672920);


--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounts_id_seq OWNED BY public.accounts.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);
ALTER TABLE ONLY public.ar_internal_metadata ALTER COLUMN key SET (pg_attver=31654472);
ALTER TABLE ONLY public.ar_internal_metadata ALTER COLUMN value SET (pg_attver=31654472);
ALTER TABLE ONLY public.ar_internal_metadata ALTER COLUMN created_at SET (pg_attver=31654472);
ALTER TABLE ONLY public.ar_internal_metadata ALTER COLUMN updated_at SET (pg_attver=31654472);


--
-- Name: entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entries (
    id integer NOT NULL,
    account_id integer NOT NULL,
    transfer_id integer NOT NULL,
    amount integer NOT NULL,
    debit boolean NOT NULL,
    CONSTRAINT entries_amount_positive CHECK ((amount > 0))
);
ALTER TABLE ONLY public.entries ALTER COLUMN id SET (pg_attver=31731616);
ALTER TABLE ONLY public.entries ALTER COLUMN account_id SET (pg_attver=31731616);
ALTER TABLE ONLY public.entries ALTER COLUMN transfer_id SET (pg_attver=31731616);
ALTER TABLE ONLY public.entries ALTER COLUMN amount SET (pg_attver=31731616);
ALTER TABLE ONLY public.entries ALTER COLUMN debit SET (pg_attver=31731616);


--
-- Name: entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entries_id_seq OWNED BY public.entries.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);
ALTER TABLE ONLY public.schema_migrations ALTER COLUMN version SET (pg_attver=31636160);


--
-- Name: transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transfers (
    id integer NOT NULL,
    external_id character varying NOT NULL,
    debit_account_id integer NOT NULL,
    credit_account_id integer NOT NULL,
    amount integer NOT NULL,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT transfers_accounts_differ CHECK ((debit_account_id <> credit_account_id)),
    CONSTRAINT transfers_amount_positive CHECK ((amount > 0))
);
ALTER TABLE ONLY public.transfers ALTER COLUMN id SET (pg_attver=31694968);
ALTER TABLE ONLY public.transfers ALTER COLUMN external_id SET (pg_attver=31694968);
ALTER TABLE ONLY public.transfers ALTER COLUMN debit_account_id SET (pg_attver=31694968);
ALTER TABLE ONLY public.transfers ALTER COLUMN credit_account_id SET (pg_attver=31694968);
ALTER TABLE ONLY public.transfers ALTER COLUMN amount SET (pg_attver=31694968);
ALTER TABLE ONLY public.transfers ALTER COLUMN created_at SET (pg_attver=31694968);


--
-- Name: transfers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.transfers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transfers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.transfers_id_seq OWNED BY public.transfers.id;


--
-- Name: account_balances id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_balances ALTER COLUMN id SET DEFAULT nextval('public.account_balances_id_seq'::regclass);


--
-- Name: accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts ALTER COLUMN id SET DEFAULT nextval('public.accounts_id_seq'::regclass);


--
-- Name: entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries ALTER COLUMN id SET DEFAULT nextval('public.entries_id_seq'::regclass);


--
-- Name: transfers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers ALTER COLUMN id SET DEFAULT nextval('public.transfers_id_seq'::regclass);


--
-- Name: account_balances account_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_balances
    ADD CONSTRAINT account_balances_pkey PRIMARY KEY (id);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: entries entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT entries_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: transfers transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_pkey PRIMARY KEY (id);


--
-- Name: index_account_balances_on_account_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_balances_on_account_id_and_id ON public.account_balances USING btree (account_id, id);


--
-- Name: index_accounts_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_external_id ON public.accounts USING btree (external_id);


--
-- Name: index_entries_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entries_on_account_id ON public.entries USING btree (account_id);


--
-- Name: index_entries_on_transfer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entries_on_transfer_id ON public.entries USING btree (transfer_id);


--
-- Name: index_entries_on_transfer_id_and_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_entries_on_transfer_id_and_account_id ON public.entries USING btree (transfer_id, account_id);


--
-- Name: index_transfers_on_credit_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transfers_on_credit_account_id ON public.transfers USING btree (credit_account_id);


--
-- Name: index_transfers_on_debit_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transfers_on_debit_account_id ON public.transfers USING btree (debit_account_id);


--
-- Name: index_transfers_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_transfers_on_external_id ON public.transfers USING btree (external_id);


--
-- Name: account_balances prevent_immutable_record_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER prevent_immutable_record_mutation BEFORE DELETE OR UPDATE ON public.account_balances FOR EACH ROW EXECUTE FUNCTION public.prevent_immutable_record_mutation();


--
-- Name: accounts prevent_immutable_record_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER prevent_immutable_record_mutation BEFORE DELETE OR UPDATE ON public.accounts FOR EACH ROW EXECUTE FUNCTION public.prevent_immutable_record_mutation();


--
-- Name: entries prevent_immutable_record_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER prevent_immutable_record_mutation BEFORE DELETE OR UPDATE ON public.entries FOR EACH ROW EXECUTE FUNCTION public.prevent_immutable_record_mutation();


--
-- Name: transfers prevent_immutable_record_mutation; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER prevent_immutable_record_mutation BEFORE DELETE OR UPDATE ON public.transfers FOR EACH ROW EXECUTE FUNCTION public.prevent_immutable_record_mutation();


--
-- Name: account_balances require_tracked_account_for_balance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER require_tracked_account_for_balance BEFORE INSERT ON public.account_balances FOR EACH ROW EXECUTE FUNCTION public.require_tracked_account_for_balance();


--
-- Name: entries fk_rails_37a3feaeb6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT fk_rails_37a3feaeb6 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: transfers fk_rails_462e999cdf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_462e999cdf FOREIGN KEY (credit_account_id) REFERENCES public.accounts(id);


--
-- Name: transfers fk_rails_a88c1035b3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_a88c1035b3 FOREIGN KEY (debit_account_id) REFERENCES public.accounts(id);


--
-- Name: entries fk_rails_c31140256b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT fk_rails_c31140256b FOREIGN KEY (transfer_id) REFERENCES public.transfers(id);


--
-- Name: account_balances fk_rails_f3e5781e9c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_balances
    ADD CONSTRAINT fk_rails_f3e5781e9c FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261113034730');
