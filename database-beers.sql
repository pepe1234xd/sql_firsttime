--create database 
CREATE DATABASE beer_db
    WITH 
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'Spanish_Mexico.1252'
    LC_CTYPE = 'Spanish_Mexico.1252'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1;
--create beers table
CREATE TABLE IF NOT EXISTS public.beers
(
    beer_id integer NOT NULL DEFAULT nextval('beers_beer_id_seq'::regclass),
    name character varying(50) COLLATE pg_catalog."default" NOT NULL,
    price numeric(4,2) NOT NULL,
    CONSTRAINT beer_id PRIMARY KEY (beer_id),
    CONSTRAINT uq_name UNIQUE (name)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.beers
    OWNER to postgres;
--create sales table
CREATE TABLE IF NOT EXISTS public.sales
(
    sale_id uuid NOT NULL,
    sale_date timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT sales_pkey PRIMARY KEY (sale_id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.sales
    OWNER to postgres;
--create acounts table
CREATE TABLE IF NOT EXISTS public.acounts
(
    acount_id integer NOT NULL DEFAULT nextval('acounts_acount_id_seq'::regclass),
    amount numeric(12,2) NOT NULL,
    name character varying(50) COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT acounts_pkey PRIMARY KEY (acount_id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.acounts
    OWNER to postgres;
--create a bill table
CREATE TABLE IF NOT EXISTS public.bills
(
    sale_id uuid NOT NULL,
    beer_id integer NOT NULL,
    CONSTRAINT fk_beer_id FOREIGN KEY (beer_id)
        REFERENCES public.beers (beer_id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT fk_sale_id FOREIGN KEY (sale_id)
        REFERENCES public.sales (sale_id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.bills
    OWNER to postgres;
--create a notes table
CREATE TABLE IF NOT EXISTS public.notes
(
    beer_id integer NOT NULL DEFAULT nextval('notes_beer_id_seq'::regclass),
    note character varying(2000) COLLATE pg_catalog."default",
    CONSTRAINT fk_beer_id FOREIGN KEY (beer_id)
        REFERENCES public.beers (beer_id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.notes
    OWNER to postgres;
--create a type
CREATE TYPE public.responce_one AS
(
	sale_id uuid,
	account_id integer,
	sale_date time with time zone,
	out_status character varying(25)
);

ALTER TYPE public.responce_one
    OWNER TO postgres;
--function create_sale
CREATE OR REPLACE FUNCTION public.fc_create_sale(
	param_beer_ids integer[],
	param_account_id integer,
	param_sale_id uuid,
	param_sale_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP)
    RETURNS responce_one
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
	out_sale responce_one;
    var_beer_id integer;
    var_beer_price numeric;
	var_sale_price_amount numeric := 0;
BEGIN

    -- Checking account exists
	IF NOT EXISTS(SELECT * FROM acounts WHERE acount_id=param_account_id) THEN
		out_sale.out_status := 'account_id_not_found';
		RETURN out_sale;
	END IF;

    -- Creates a sale
    INSERT INTO sales(sale_id,sale_date) VALUES(param_sale_id, param_sale_date);

    -- Stores all the beer sales in one
    FOREACH var_beer_id IN ARRAY param_beer_ids
    LOOP
        SELECT price INTO var_beer_price FROM beers WHERE beer_id=var_beer_id;
        IF var_beer_price IS NULL THEN
            out_sale.out_status := 'beer_not_found';
			RETURN out_sale;
        ELSE
            var_sale_price_amount := var_sale_price_amount + var_beer_price;
            INSERT INTO bills(sale_id,beer_id) VALUES(param_sale_id,var_beer_id);
        END IF;
    END LOOP;

    -- Updating account capital
    UPDATE acounts SET amount = amount + var_sale_price_amount WHERE acount_id = param_account_id;
	
    out_sale.sale_id := param_sale_id;
    out_sale.sale_date := param_sale_date;
    out_sale.account_id := param_account_id;
	out_sale.out_status := 'succeed';
	RETURN out_sale;
END

$BODY$;

ALTER FUNCTION public.fc_create_sale(integer[], integer, uuid, timestamp with time zone)
    OWNER TO postgres;
--function delete sale
CREATE OR REPLACE FUNCTION public.fc_delete_sale(
	param_account_id integer,
	param_sale_id uuid)
    RETURNS responce_one
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
	out_sale responce_one;
	var_contador integer;
    var_beer_id integer;
	var_beers_id integer[];
    var_beer_price numeric;
	var_sale_price_amount numeric := 0;
BEGIN
    -- Checking account exists
	IF NOT EXISTS(SELECT * FROM sales WHERE sale_id=param_sale_id) THEN
		out_sale.out_status := 'sale_id_not_found';
		RETURN out_sale;
	END IF;
	--obtain all of the sales with the same sale_id
	SELECT ARRAY(SELECT beer_id INTO var_beers_id FROM bills WHERE sale_id=param_sale_id);
	--delete the bills
	DELETE FROM bill WHERE sale_id=param_sale_id;
	--getting the total of the sale
	    FOREACH var_beer_id IN ARRAY var_beers_id
    LOOP
        SELECT price INTO var_beer_price FROM beers WHERE beer_id=var_beer_id;
        IF var_beer_price IS NULL THEN
            out_sale.out_status := 'beer_not_found';
			RETURN out_sale;
        ELSE
            var_sale_price_amount := var_sale_price_amount + var_beer_price;
            INSERT INTO bills(sale_id,beer_id) VALUES(param_sale_id,var_beer_id);
        END IF;
    END LOOP;
	    -- Updating account capital
    UPDATE acounts SET amount = amount - var_sale_price_amount WHERE acount_id = param_account_id;
    out_sale.sale_id := param_sale_id;
    out_sale.sale_date := CURRENT_TIMESTAMP;
    out_sale.account_id := param_account_id;
	out_sale.out_status := 'succeed';
	RETURN out_sale;
END

$BODY$;

ALTER FUNCTION public.fc_delete_sale(integer, uuid)
    OWNER TO postgres;
