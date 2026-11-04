CREATE OR REPLACE PROCEDURE зарегистрировать_участницу(
    IN p_id_участника bigint,
    IN p_id_мероприятия bigint
)
LANGUAGE plpgsql
AS $$
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
$$;
