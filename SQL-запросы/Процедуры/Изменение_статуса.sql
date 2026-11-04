CREATE OR REPLACE PROCEDURE изменить_статус_регистрации(
    IN p_id_регистрации bigint,
    IN p_новый_статус text
)
LANGUAGE plpgsql
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
