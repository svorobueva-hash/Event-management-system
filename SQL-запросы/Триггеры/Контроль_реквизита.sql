CREATE OR REPLACE FUNCTION проверить_реквизит()
RETURNS TRIGGER
LANGUAGE plpgsql
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

DROP TRIGGER IF EXISTS триггер_проверки_реквизита
ON реквизит;

CREATE TRIGGER триггер_проверки_реквизита
BEFORE INSERT OR UPDATE
ON реквизит
FOR EACH ROW
EXECUTE FUNCTION проверить_реквизит();
