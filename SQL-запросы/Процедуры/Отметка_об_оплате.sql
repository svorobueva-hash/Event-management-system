CREATE OR REPLACE PROCEDURE отметить_оплату_взноса(
    IN p_id_регистрации bigint
)
LANGUAGE plpgsql
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
