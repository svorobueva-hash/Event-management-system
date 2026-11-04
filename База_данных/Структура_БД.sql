


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE PROCEDURE "public"."зарегистрировать_участницу"(IN "p_id_участника" bigint, IN "p_id_мероприятия" bigint)
    LANGUAGE "plpgsql"
    AS $_$
DECLARE
    v_id_регистрации bigint;
    v_поле_даты text;
    v_количество_полей integer;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM участники
        WHERE id_участника = p_id_участника
    ) THEN
        RAISE EXCEPTION
            'Участница с ID % не найдена',
            p_id_участника;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM мероприятия
        WHERE id_мероприятия = p_id_мероприятия
    ) THEN
        RAISE EXCEPTION
            'Мероприятие с ID % не найдено',
            p_id_мероприятия;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM регистрация_участников
        WHERE id_участника = p_id_участника
          AND id_мероприятия = p_id_мероприятия
    ) THEN
        RAISE EXCEPTION
            'Участница % уже зарегистрирована на мероприятие %',
            p_id_участника,
            p_id_мероприятия;
    END IF;

    SELECT COUNT(*), MIN(column_name)
    INTO v_количество_полей, v_поле_даты
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'регистрация_участников'
      AND column_name LIKE 'дата_регистрации%';

    IF v_количество_полей <> 1 THEN
        RAISE EXCEPTION
            'Не удалось определить столбец даты регистрации';
    END IF;

    EXECUTE format(
        'INSERT INTO public.регистрация_участников
        (
            id_участника,
            id_мероприятия,
            %I,
            статус_участия,
            отметка_о_взносе
        )
        VALUES ($1, $2, CURRENT_DATE,
                ''Ожидает подтверждения'', false)
        RETURNING id_регистрации',
        v_поле_даты
    )
    INTO v_id_регистрации
    USING p_id_участника, p_id_мероприятия;

    RAISE NOTICE
        'Участница % зарегистрирована на мероприятие %. ID регистрации: %',
        p_id_участника,
        p_id_мероприятия,
        v_id_регистрации;
END;
$_$;


ALTER PROCEDURE "public"."зарегистрировать_участницу"(IN "p_id_участника" bigint, IN "p_id_мероприятия" bigint) OWNER TO "postgres";


CREATE PROCEDURE "public"."изменить_статус_регистрации"(IN "p_id_регистрации" bigint, IN "p_новый_статус" "text")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_старый_статус text;
BEGIN

    IF p_новый_статус IS NULL
       OR p_новый_статус NOT IN (
           'Подтверждено',
           'Ожидает подтверждения',
           'Отменено'
       ) THEN
        RAISE EXCEPTION
            'Недопустимый статус: %',
            p_новый_статус;
    END IF;

    SELECT статус_участия
    INTO v_старый_статус
    FROM регистрация_участников
    WHERE id_регистрации = p_id_регистрации;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Регистрация с ID % не найдена',
            p_id_регистрации;
    END IF;

    UPDATE регистрация_участников
    SET статус_участия = p_новый_статус
    WHERE id_регистрации = p_id_регистрации;

    RAISE NOTICE
        'Регистрация %: статус изменён с "%" на "%"',
        p_id_регистрации,
        v_старый_статус,
        p_новый_статус;
END;
$$;


ALTER PROCEDURE "public"."изменить_статус_регистрации"(IN "p_id_регистрации" bigint, IN "p_новый_статус" "text") OWNER TO "postgres";


CREATE PROCEDURE "public"."отметить_оплату_взноса"(IN "p_id_регистрации" bigint)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_сумма numeric;
BEGIN

    SELECT u.взнос_участников
    INTO v_сумма
    FROM регистрация_участников AS r
    JOIN участники AS u
        ON r.id_участника = u.id_участника
    WHERE r.id_регистрации = p_id_регистрации;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Регистрация с ID % не найдена',
            p_id_регистрации;
    END IF;

    IF v_сумма IS NULL OR v_сумма <= 0 THEN
        RAISE EXCEPTION
            'Для регистрации с ID % нет платного взноса',
            p_id_регистрации;
    END IF;

    UPDATE регистрация_участников
    SET отметка_о_взносе = true
    WHERE id_регистрации = p_id_регистрации;

    RAISE NOTICE
        'Оплата регистрации % отмечена',
        p_id_регистрации;
END;
$$;


ALTER PROCEDURE "public"."отметить_оплату_взноса"(IN "p_id_регистрации" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."проверить_повторную_регистрацию"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM регистрация_участников AS r
        WHERE r.id_участника = NEW.id_участника
          AND r.id_мероприятия = NEW.id_мероприятия
          AND r.id_регистрации IS DISTINCT FROM NEW.id_регистрации
    ) THEN
        RAISE EXCEPTION
            'Участница % уже зарегистрирована на мероприятие %',
            NEW.id_участника,
            NEW.id_мероприятия;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."проверить_повторную_регистрацию"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."проверить_реквизит"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN

    IF NEW.количество < 0 THEN
        RAISE EXCEPTION
            'Количество реквизита не может быть отрицательным';
    END IF;


    IF NEW.цена < 0 THEN
        RAISE EXCEPTION
            'Цена реквизита не может быть отрицательной';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."проверить_реквизит"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."мероприятия" (
    "id_мероприятия" bigint NOT NULL,
    "название_мероприятия" "text" NOT NULL,
    "дата_проведения" "date" NOT NULL,
    "место_проведения" "text" NOT NULL
);


ALTER TABLE "public"."мероприятия" OWNER TO "postgres";


COMMENT ON TABLE "public"."мероприятия" IS 'Хранение информации о спортивных мероприятиях, включая их названия, даты проведения и места организации.';



CREATE TABLE IF NOT EXISTS "public"."регистрация_участников" (
    "id_регистрации" bigint NOT NULL,
    "id_участника" bigint NOT NULL,
    "id_мероприятия" bigint NOT NULL,
    "дата_регистрации_участника_на_мер" "date" NOT NULL,
    "статус_участия" "text" NOT NULL,
    "отметка_о_взносе" boolean NOT NULL
);


ALTER TABLE "public"."регистрация_участников" OWNER TO "postgres";


COMMENT ON TABLE "public"."регистрация_участников" IS 'Хранение сведений о регистрации участников на спортивные мероприятия, включая дату регистрации, статус участия и отметку об оплате взноса.';



CREATE TABLE IF NOT EXISTS "public"."участники" (
    "id_участника" bigint NOT NULL,
    "фио" "text" NOT NULL,
    "дата_рождения" "date" NOT NULL,
    "номер_удостоверения" "text",
    "телефон" "text" NOT NULL,
    "номер_страховки" "text",
    "взнос_участников" numeric NOT NULL
);


ALTER TABLE "public"."участники" OWNER TO "postgres";


COMMENT ON TABLE "public"."участники" IS 'Хранение персональных данных участников спортивных мероприятий, включая ФИО, дату рождения, контактную информацию, номера удостоверений, страховок и сведения об участнических взносах.';



CREATE OR REPLACE VIEW "public"."анализ_взносов_по_мероприятиям" AS
 SELECT "m"."название_мероприятия",
    "m"."дата_проведения",
    "count"(DISTINCT "r"."id_участника") AS "количество_участниц",
    "min"("u"."взнос_участников") FILTER (WHERE ("u"."взнос_участников" > (0)::numeric)) AS "минимальный_взнос",
    "max"("u"."взнос_участников") FILTER (WHERE ("u"."взнос_участников" > (0)::numeric)) AS "максимальный_взнос",
    "round"("avg"("u"."взнос_участников") FILTER (WHERE ("u"."взнос_участников" > (0)::numeric)), 2) AS "средний_взнос",
    "count"(*) FILTER (WHERE (("r"."отметка_о_взносе" = false) AND ("u"."взнос_участников" > (0)::numeric))) AS "неоплаченные_регистрации",
    COALESCE("sum"("u"."взнос_участников") FILTER (WHERE ("r"."отметка_о_взносе" = true)), (0)::numeric) AS "получено_взносов"
   FROM (("public"."регистрация_участников" "r"
     JOIN "public"."участники" "u" ON (("r"."id_участника" = "u"."id_участника")))
     JOIN "public"."мероприятия" "m" ON (("r"."id_мероприятия" = "m"."id_мероприятия")))
  GROUP BY "m"."id_мероприятия", "m"."название_мероприятия", "m"."дата_проведения"
  ORDER BY "m"."дата_проведения";


ALTER VIEW "public"."анализ_взносов_по_мероприятиям" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."организация_мероприятий" (
    "id_организации" bigint NOT NULL,
    "id_сотрудника" bigint NOT NULL,
    "id_регистрации" bigint NOT NULL,
    "id_пакета_документов" bigint NOT NULL,
    "id_реквизита" bigint NOT NULL,
    "бюджет" numeric NOT NULL
);


ALTER TABLE "public"."организация_мероприятий" OWNER TO "postgres";


COMMENT ON TABLE "public"."организация_мероприятий" IS 'Хранение сведений об организации спортивных мероприятий, включая ответственных сотрудников, зарегистрированных участников, документацию, используемый реквизит и бюджет мероприятия.';



CREATE TABLE IF NOT EXISTS "public"."пакет_документов" (
    "id_пакета_документов" bigint NOT NULL,
    "название_документа" "text" NOT NULL,
    "предмет_документа" "text" NOT NULL,
    "номер_документа" "text",
    "дата" "date" NOT NULL,
    "регистрационный_номер" "text"
);


ALTER TABLE "public"."пакет_документов" OWNER TO "postgres";


COMMENT ON TABLE "public"."пакет_документов" IS 'Хранение сведений о документах, необходимых для организации и проведения спортивных мероприятий, включая название, назначение, номер документа, дату оформления и регистрационный номер.';



CREATE TABLE IF NOT EXISTS "public"."сотрудники" (
    "id_сотрудника" bigint NOT NULL,
    "фио" "text" NOT NULL,
    "дата_рождения" "date" NOT NULL,
    "номер_удостоверения" "text",
    "телефон" "text" NOT NULL
);


ALTER TABLE "public"."сотрудники" OWNER TO "postgres";


COMMENT ON TABLE "public"."сотрудники" IS 'Хранение персональных и контактных данных сотрудников, ответственных за организацию и проведение спортивных мероприятий, включая ФИО, дату рождения, номер удостоверения и телефон.';



CREATE OR REPLACE VIEW "public"."документы_выездных_мероприятий" AS
 SELECT "m"."название_мероприятия",
    "m"."дата_проведения",
    "s"."фио" AS "ответственный_сотрудник",
    "string_agg"(DISTINCT "d"."название_документа", ', '::"text" ORDER BY "d"."название_документа") AS "название_документа",
    "string_agg"(DISTINCT "d"."предмет_документа", ', '::"text" ORDER BY "d"."предмет_документа") AS "предмет_документа",
    "string_agg"(DISTINCT "d"."регистрационный_номер", ', '::"text" ORDER BY "d"."регистрационный_номер") AS "регистрационный_номер",
    "count"(DISTINCT "r"."id_регистрации") AS "количество_регистраций",
    "total"."всего_участниц" AS "всего_участниц_на_мероприятии"
   FROM ((((("public"."организация_мероприятий" "o"
     JOIN "public"."регистрация_участников" "r" ON (("o"."id_регистрации" = "r"."id_регистрации")))
     JOIN "public"."мероприятия" "m" ON (("r"."id_мероприятия" = "m"."id_мероприятия")))
     JOIN "public"."сотрудники" "s" ON (("o"."id_сотрудника" = "s"."id_сотрудника")))
     JOIN "public"."пакет_документов" "d" ON (("o"."id_пакета_документов" = "d"."id_пакета_документов")))
     JOIN ( SELECT "регистрация_участников"."id_мероприятия",
            "count"(DISTINCT "регистрация_участников"."id_участника") AS "всего_участниц"
           FROM "public"."регистрация_участников"
          GROUP BY "регистрация_участников"."id_мероприятия") "total" ON (("total"."id_мероприятия" = "m"."id_мероприятия")))
  WHERE ("m"."название_мероприятия" = 'Кубок Москвы по чир спорту'::"text")
  GROUP BY "m"."название_мероприятия", "m"."дата_проведения", "s"."id_сотрудника", "s"."фио", "total"."всего_участниц"
  ORDER BY "s"."фио";


ALTER VIEW "public"."документы_выездных_мероприятий" OWNER TO "postgres";


ALTER TABLE "public"."мероприятия" ALTER COLUMN "id_мероприятия" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."мероприятия_id_мероприятия_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."неоплаченные_взносы" AS
 SELECT "n"."фио",
    "m"."название_мероприятия",
    "m"."дата_проведения",
    "n"."взнос_участников",
    "s"."статус_участия"
   FROM (("public"."регистрация_участников" "s"
     JOIN "public"."участники" "n" ON (("n"."id_участника" = "s"."id_участника")))
     JOIN "public"."мероприятия" "m" ON (("m"."id_мероприятия" = "s"."id_мероприятия")))
  WHERE (("s"."отметка_о_взносе" = false) AND ("n"."взнос_участников" > (0)::numeric));


ALTER VIEW "public"."неоплаченные_взносы" OWNER TO "postgres";


ALTER TABLE "public"."организация_мероприятий" ALTER COLUMN "id_организации" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."организация_мероп_id_организации_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."пакет_документов" ALTER COLUMN "id_пакета_документов" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."пакет_документо_id_пакета_докуме_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."регистрация_участников" ALTER COLUMN "id_регистрации" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."регистрация_участ_id_регистрации_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."реквизит" (
    "id_реквизита" bigint NOT NULL,
    "наименование" "text" NOT NULL,
    "количество" integer NOT NULL,
    "цена" numeric NOT NULL
);


ALTER TABLE "public"."реквизит" OWNER TO "postgres";


COMMENT ON TABLE "public"."реквизит" IS 'Хранение сведений о материально-технических ресурсах, необходимых для организации спортивных мероприятий, включая наименование, количество и стоимость реквизита.';



ALTER TABLE "public"."реквизит" ALTER COLUMN "id_реквизита" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."реквизит_id_реквизита_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."сотрудники" ALTER COLUMN "id_сотрудника" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."сотрудники_id_сотрудника_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE OR REPLACE VIEW "public"."список_регистраций" AS
 SELECT "у"."фио",
    "м"."название_мероприятия",
    "р"."статус_участия",
    "р"."отметка_о_взносе"
   FROM (("public"."регистрация_участников" "р"
     JOIN "public"."участники" "у" ON (("р"."id_участника" = "у"."id_участника")))
     JOIN "public"."мероприятия" "м" ON (("р"."id_мероприятия" = "м"."id_мероприятия")));


ALTER VIEW "public"."список_регистраций" OWNER TO "postgres";


ALTER TABLE "public"."участники" ALTER COLUMN "id_участника" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."участники_id_участника_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY "public"."мероприятия"
    ADD CONSTRAINT "мероприятия_pkey" PRIMARY KEY ("id_мероприятия");



ALTER TABLE ONLY "public"."организация_мероприятий"
    ADD CONSTRAINT "организация_мероприятия_pkey" PRIMARY KEY ("id_организации");



ALTER TABLE ONLY "public"."пакет_документов"
    ADD CONSTRAINT "пакет_документов_pkey" PRIMARY KEY ("id_пакета_документов");



ALTER TABLE ONLY "public"."регистрация_участников"
    ADD CONSTRAINT "регистрация_участников_pkey" PRIMARY KEY ("id_регистрации");



ALTER TABLE ONLY "public"."реквизит"
    ADD CONSTRAINT "реквизит_pkey" PRIMARY KEY ("id_реквизита");



ALTER TABLE ONLY "public"."сотрудники"
    ADD CONSTRAINT "сотрудники_pkey" PRIMARY KEY ("id_сотрудника");



ALTER TABLE ONLY "public"."участники"
    ADD CONSTRAINT "участники_pkey" PRIMARY KEY ("id_участника");



CREATE OR REPLACE TRIGGER "триггер_повторной_регистрации" BEFORE INSERT OR UPDATE OF "id_участника", "id_мероприятия" ON "public"."регистрация_участников" FOR EACH ROW EXECUTE FUNCTION "public"."проверить_повторную_регистрацию"();



CREATE OR REPLACE TRIGGER "триггер_проверки_реквизита" BEFORE INSERT OR UPDATE ON "public"."реквизит" FOR EACH ROW EXECUTE FUNCTION "public"."проверить_реквизит"();



ALTER TABLE ONLY "public"."организация_мероприятий"
    ADD CONSTRAINT "организация_мер_id_пакета_докуме_fkey" FOREIGN KEY ("id_пакета_документов") REFERENCES "public"."пакет_документов"("id_пакета_документов");



ALTER TABLE ONLY "public"."организация_мероприятий"
    ADD CONSTRAINT "организация_меро_id_регистрации_fkey" FOREIGN KEY ("id_регистрации") REFERENCES "public"."регистрация_участников"("id_регистрации");



ALTER TABLE ONLY "public"."организация_мероприятий"
    ADD CONSTRAINT "организация_мероп_id_сотрудника_fkey" FOREIGN KEY ("id_сотрудника") REFERENCES "public"."сотрудники"("id_сотрудника");



ALTER TABLE ONLY "public"."организация_мероприятий"
    ADD CONSTRAINT "организация_меропр_id_реквизита_fkey" FOREIGN KEY ("id_реквизита") REFERENCES "public"."реквизит"("id_реквизита");



ALTER TABLE ONLY "public"."регистрация_участников"
    ADD CONSTRAINT "регистрация_учас_id_мероприятия_fkey" FOREIGN KEY ("id_мероприятия") REFERENCES "public"."мероприятия"("id_мероприятия");



ALTER TABLE ONLY "public"."регистрация_участников"
    ADD CONSTRAINT "регистрация_участн_id_участника_fkey" FOREIGN KEY ("id_участника") REFERENCES "public"."участники"("id_участника");



ALTER TABLE "public"."мероприятия" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."организация_мероприятий" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."пакет_документов" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."регистрация_участников" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."реквизит" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."сотрудники" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."участники" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON PROCEDURE "public"."зарегистрировать_участницу"(IN "p_id_участника" bigint, IN "p_id_мероприятия" bigint) TO "anon";
GRANT ALL ON PROCEDURE "public"."зарегистрировать_участницу"(IN "p_id_участника" bigint, IN "p_id_мероприятия" bigint) TO "authenticated";
GRANT ALL ON PROCEDURE "public"."зарегистрировать_участницу"(IN "p_id_участника" bigint, IN "p_id_мероприятия" bigint) TO "service_role";



GRANT ALL ON PROCEDURE "public"."изменить_статус_регистрации"(IN "p_id_регистрации" bigint, IN "p_новый_статус" "text") TO "anon";
GRANT ALL ON PROCEDURE "public"."изменить_статус_регистрации"(IN "p_id_регистрации" bigint, IN "p_новый_статус" "text") TO "authenticated";
GRANT ALL ON PROCEDURE "public"."изменить_статус_регистрации"(IN "p_id_регистрации" bigint, IN "p_новый_статус" "text") TO "service_role";



GRANT ALL ON PROCEDURE "public"."отметить_оплату_взноса"(IN "p_id_регистрации" bigint) TO "anon";
GRANT ALL ON PROCEDURE "public"."отметить_оплату_взноса"(IN "p_id_регистрации" bigint) TO "authenticated";
GRANT ALL ON PROCEDURE "public"."отметить_оплату_взноса"(IN "p_id_регистрации" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."проверить_повторную_регистрацию"() TO "anon";
GRANT ALL ON FUNCTION "public"."проверить_повторную_регистрацию"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."проверить_повторную_регистрацию"() TO "service_role";



GRANT ALL ON FUNCTION "public"."проверить_реквизит"() TO "anon";
GRANT ALL ON FUNCTION "public"."проверить_реквизит"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."проверить_реквизит"() TO "service_role";



GRANT ALL ON TABLE "public"."мероприятия" TO "anon";
GRANT ALL ON TABLE "public"."мероприятия" TO "authenticated";
GRANT ALL ON TABLE "public"."мероприятия" TO "service_role";



GRANT ALL ON TABLE "public"."регистрация_участников" TO "anon";
GRANT ALL ON TABLE "public"."регистрация_участников" TO "authenticated";
GRANT ALL ON TABLE "public"."регистрация_участников" TO "service_role";



GRANT ALL ON TABLE "public"."участники" TO "anon";
GRANT ALL ON TABLE "public"."участники" TO "authenticated";
GRANT ALL ON TABLE "public"."участники" TO "service_role";



GRANT ALL ON TABLE "public"."анализ_взносов_по_мероприятиям" TO "anon";
GRANT ALL ON TABLE "public"."анализ_взносов_по_мероприятиям" TO "authenticated";
GRANT ALL ON TABLE "public"."анализ_взносов_по_мероприятиям" TO "service_role";



GRANT ALL ON TABLE "public"."организация_мероприятий" TO "anon";
GRANT ALL ON TABLE "public"."организация_мероприятий" TO "authenticated";
GRANT ALL ON TABLE "public"."организация_мероприятий" TO "service_role";



GRANT ALL ON TABLE "public"."пакет_документов" TO "anon";
GRANT ALL ON TABLE "public"."пакет_документов" TO "authenticated";
GRANT ALL ON TABLE "public"."пакет_документов" TO "service_role";



GRANT ALL ON TABLE "public"."сотрудники" TO "anon";
GRANT ALL ON TABLE "public"."сотрудники" TO "authenticated";
GRANT ALL ON TABLE "public"."сотрудники" TO "service_role";



GRANT ALL ON TABLE "public"."документы_выездных_мероприятий" TO "anon";
GRANT ALL ON TABLE "public"."документы_выездных_мероприятий" TO "authenticated";
GRANT ALL ON TABLE "public"."документы_выездных_мероприятий" TO "service_role";



GRANT ALL ON SEQUENCE "public"."мероприятия_id_мероприятия_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."мероприятия_id_мероприятия_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."мероприятия_id_мероприятия_seq" TO "service_role";



GRANT ALL ON TABLE "public"."неоплаченные_взносы" TO "anon";
GRANT ALL ON TABLE "public"."неоплаченные_взносы" TO "authenticated";
GRANT ALL ON TABLE "public"."неоплаченные_взносы" TO "service_role";



GRANT ALL ON SEQUENCE "public"."организация_мероп_id_организации_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."организация_мероп_id_организации_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."организация_мероп_id_организации_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."пакет_документо_id_пакета_докуме_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."пакет_документо_id_пакета_докуме_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."пакет_документо_id_пакета_докуме_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."регистрация_участ_id_регистрации_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."регистрация_участ_id_регистрации_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."регистрация_участ_id_регистрации_seq" TO "service_role";



GRANT ALL ON TABLE "public"."реквизит" TO "anon";
GRANT ALL ON TABLE "public"."реквизит" TO "authenticated";
GRANT ALL ON TABLE "public"."реквизит" TO "service_role";



GRANT ALL ON SEQUENCE "public"."реквизит_id_реквизита_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."реквизит_id_реквизита_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."реквизит_id_реквизита_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."сотрудники_id_сотрудника_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."сотрудники_id_сотрудника_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."сотрудники_id_сотрудника_seq" TO "service_role";



GRANT ALL ON TABLE "public"."список_регистраций" TO "anon";
GRANT ALL ON TABLE "public"."список_регистраций" TO "authenticated";
GRANT ALL ON TABLE "public"."список_регистраций" TO "service_role";



GRANT ALL ON SEQUENCE "public"."участники_id_участника_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."участники_id_участника_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."участники_id_участника_seq" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







