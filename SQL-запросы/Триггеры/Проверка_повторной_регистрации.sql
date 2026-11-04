CREATE OR REPLACE FUNCTION проверить_повторную_регистрацию()
RETURNS TRIGGER
LANGUAGE plpgsql
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

DROP TRIGGER IF EXISTS триггер_повторной_регистрации
ON регистрация_участников;

CREATE TRIGGER триггер_повторной_регистрации
BEFORE INSERT OR UPDATE OF id_участника, id_мероприятия
ON регистрация_участников
FOR EACH ROW
EXECUTE FUNCTION проверить_повторную_регистрацию();
