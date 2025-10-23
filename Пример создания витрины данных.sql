DROP TABLE IF EXISTS onecdata.base;
CREATE TABLE onecdata.base AS

with sleep_clients as ( --ОПРЕДЕЛЯЕМ СПЯЩИХ КЛИЕНТОВ И ДАТУ ЗАКРЫТИЯ ЗАЙМА
    select
        ld.cl_id,
        max(s.period)::date as end_loan_dt,
        max(s.period) as loan_fact_end_dt
    from onecdata.statuses s
        join onecdata.statuses_status ss on ss.id = s.status
        join onecdata.loans_events_data ld on ld.key_app = s.id_app
            and ld.dtstartloan is not null
    where ss.link in ('ЗаймПогашен', 'БАНКРОТ', 'ОшибкаТехническая', 'Выбывшие',
                                     'Продажа', 'ДоговорНеЗаключен', 'МВД_Погашен')
    group by 1
),
in_loan_clients as ( --ОПРЕДЕЛЯЕМ КЛИЕНТОВ НАХОДЯЩИХСЯ В ЗАЙМЕ
    select
        ld.cl_id,
        lc.od
    from onecdata.last_day_cycle lc
        join onecdata.loans_events_data ld on ld.key_app = lc.key_app
    where lc.today_date = current_date - interval '1 day' and lc.od > 0
),
cp_status as ( --ОПРЕДЕЛЯЕМ СТАТУСЫ ИЗ ТАБЛИЦЫ cp
    select
        ld.cl_id,
        max(prop) as prop, --max для агрегирования значение для каждого клиента одно
        max(dt_prop) as dt_prop --max для агрегирования значение для каждого клиента одно
    from (
        select
            cp.*,
            row_number() over (partition by ag_id order by date_dt desc) as rn
        from onecdata.counter_prop cp
        where (cp.prop = 'ОтказОтРасслыки'
           or cp.prop = 'ЧС')
           or cp.dt_prop = 'УдаленЛК'
    ) r
        join onecdata.loans_events_data ld on ld.ag_id = r.ag_id
    where rn = 1
    group by 1
),
start_del_lk as ( --ОПРЕДЕЛЯЕМ КЛИЕНТОВ, КОТОРЫЕ НАЧАЛИ УДАЛЕНИЕ ЛК
    select
        ld.cl_id,
        max(date_dt) as start_del_dt
    from (
        select
            *,
            lead(cp.dt_prop) over (partition by cp.ag_id order by cp.date_dt) as next_value
        from onecdata.counter_prop cp
        where prop = 'УдалениеЛК') as t
    join onecdata.loans_events_data ld on ld.ag_id = t.ag_id
    where dt_prop = 'НачалУдалениеЛК'
        and current_date::date - date_dt::date < 31
        and next_value is null --ОСТАВЛЯЕМ ТЕХ КЛИЕНТОВ, КОТОРЫЕ НЕ ПОЛУЧИЛИ СЛДЕУЮЩЕГО СТАТУСА В ТЕЧЕНИИ 31 ДНЯ ПОСЛЕ НАЧАЛА УДАЛЕНИЯ ЛК.
    -- ТАК КАК, ЛЮБОЕ ПОЛУЧЕНИЕ СЛЕДУЮЩЕГО СТАТУСА ОЗНАЧАЕТ, ЧТО КЛИНЕТ УДАЛИЛ СВОЙ ЛК ИЛИ ОТКАЗАЛСЯ ОТ УДАЛЕНИЯ(FALSE)
    group by 1
),
arb_status as ( --ОПРЕДЕЛЯЕМ СТАТУСЫ ИЗ ТАБЛИЦЫ arb
    select
        cl_id,
        max(start_block) as start_block
    from onecdata.reject_block arb
    where arb.block_forever = true or current_date between arb.start_block and arb.end_block
    group by 1
),
client_last_delay as ( --ОПРЕЛЕЛЯЕМ ПОСЛЕДНЕЕ ЗНАЧНИЕ ПРОСРОЧКИ В ДЕНЬ ЗАКРЫТИЯ ЗАЙМА ДЛЯ КАЖДОГО КЛИНЕТА
    select cl_id, delay
        from (
            select
                row_number() over (partition by ld.cl_id order by lc.today_date desc) rn,
                ld.cl_id,
                lc.delay as delay
            from onecdata.last_day_cycle lc
                join onecdata.loans_events_data ld on ld.key_app = lc.key_app
            where lc.od = 0
             ) row
        where rn = 1
),
limits as ( --ОПРЕЛЕЛЯЕМ ПОСЛЕДНЕЕ ЗНАЧНИЕ ЛИМИТА ДЛЯ КАЖДОГО ИЗ КЛИНЕТОВ
select
    cl_id,
    lim_prod_1 as lim_prod_1,
    lim_prod_2 as lim_prod_2
from (
    select
        cl_id,
        lim_prod_1,
        lim_prod_2,
        row_number() over (partition by cl_id order by last_limit desc) as rn
    from onecdata.limit
) t
where rn = 1
),
all_table as ( --СОБИРАЕМ ХАРАКТЕРИСТИКИ ДЛЯ ВСЕХ КЛИЕНТОВ
select
    ld.cl_id,
    sum(case when ld.dtstartloan is not null then 1 end) as num_loan,
    sum(case when ld.app_stat = 'Продажа' then 1 else 0 end) as solds,
    sum(case when ld.app_stat = 'БАНКРОТ' then 1 else 0 end) as bankrupts,
    sum(case when ld.app_stat = 'МВД' then 1 else 0 end) as mvd,
    sum(case when ld.app_stat is null then 1 else 0 end) as not_status,
    sum(case when (date_trunc('day', ld.dtstartloan) = current_date and ld.app_stat = 'ЗаймВыдан') or (lc.cl_id is not null and lc.od is not null) then 1 else 0 end) as activ_loan,--В ТОМ ЧИСЛЕ, ТЕХ КТО ОФОРМИЛ ЗАЙМ СЕГОДНЯ
    max(case when sc.end_loan_dt is not null and ld.dtstartloan is not null then current_date - sc.end_loan_dt else 0 end) as sleep_days, --max для агрегирования, так как, встречаются клиенты с множеством одинаковых значений
    sum(case when lc.cl_id is null and ld.app_dt > sc.loan_fact_end_dt then 1 else 0 end) as new_loan_after_end,--lc.cl_id is null ЧТОБЫ ОТСЕЯТЬ ТЕХ, КТО СЕЙЧАС ЗАЙМЕ. ТАК КАК, УСЛОВИЕ > У НИХ СОБЛЮДЕНО
    sum(case when cp.prop = 'ОтказОтРассылок' then 1 else 0 end) as in_unsubscribe,
    sum(case when cp.dt_prop = 'НачалУдалениеЛК' then 1 else 0 end) as in_del_lk,
    sum(case when cp.prop = 'ЧС' then 1 else 0 end) as in_black_list,
    sum(case when sd.start_del_dt is not null then 1 else 0 end) as in_start_del_lk,
    sum(case when ars.start_block is not null then 1 else 0 end) as in_block,
    max(cld.delay) as delay,--max для агрегирования значение для каждого клиента одно
    max(l.lim_prod_1) as lim_prod_1,--max для агрегирования значение для каждого клиента одно
    max(l.lim_prod_2) as lim_prod_2--max для агрегирования значение для каждого клиента одно
from onecdata.loans_events_data ld
    left join in_loan_clients lc on lc.cl_id = ld.cl_id
    left join sleep_clients sc on sc.cl_id = ld.cl_id
    left join cp_status cp on cp.cl_id = ld.cl_id
    left join start_del_lk sd on sd.cl_id = ld.cl_id
    left join arb_status ars on ars.cl_id = ld.cl_id
    left join client_last_delay cld on cld.cl_id = ld.cl_id
    left join limits l on l.cl_id = ld.cl_id
    group by 1
)
--ФИНАЛЬНАЯ ТАБЛИЦА
    select
        case when at.activ_loan > 0 then 'Да' else 'Hет' end as in_activ_loan,
        case when at.solds > 0 then 'Да' else 'Hет' end as is_solds_loan,
        case when at.mvd > 0 then 'Да' else 'Hет' end as in_mvd,
        case when at.bankrupts > 0 then 'Да' else 'Hет' end as in_bankrupts,
        case when at.in_black_list > 0 then 'Да' else 'Hет' end as in_black_list,
        case when at.in_del_lk > 0 then 'Да' else 'Hет' end as in_del_lk,
        case when at.in_start_del_lk > 0 then 'Да' else 'Hет' end as in_start_del_lk,
        case when at.not_status > 0 then 'Да' else 'Hет' end as in_not_status,
        case when at.in_unsubscribe > 0 then 'Да' else 'Hет' end as unsubscribe,
        case when at.in_block > 0 then 'Да' else 'Hет' end as block,
        case
            when at.num_loan is null then 'Займы не выдавались'
            when at.num_loan = 1 then 'a. 1'
            when at.num_loan = 2 then 'b. 2'
            when at.num_loan = 3 then 'c. 3'
            when at.num_loan <= 5 then 'd. 4-5'
            when at.num_loan <= 10 then 'e. 6-10'
            else 'f. 10+'
        end as num_loan, --определяем номер займа
        case
            when at.delay is null then 'Просрочки не учитываются'
            when at.delay <= 0 then 'a. Нет просрочек'
            when at.delay <= 5 then 'b. 1-5 дней просрочки'
            when at.delay <= 30 then 'c. 6-30 дней просрочки'
            when at.delay <= 60 then 'd. 31-60 дней просрочки'
            else 'e. более 60 дней просрочки'
        end as days_delay, --категоризация просрочки
        case
            when at.activ_loan > 0 then 'В займе'
            when at.activ_loan = 0 and at.sleep_days is null then 'Отсутствует закрытый займ'
            when at.activ_loan = 0 and at.sleep_days <= 30 then 'a. 0-30'
            when at.activ_loan = 0 and at.sleep_days <= 60 then 'b. 31-60'
            when at.activ_loan = 0 and at.sleep_days <= 90 then 'c. 61-90'
            when at.activ_loan = 0 and at.sleep_days <= 180 then 'd. 91-180'
            when at.activ_loan = 0 and at.sleep_days <= 360 then 'e. 181-360'
            when at.activ_loan = 0 and at.sleep_days <= 720 then 'f. 361-720'
            when at.activ_loan = 0 and at.sleep_days <= 1080 then 'g. 721-1080'
            when at.activ_loan = 0 and at.sleep_days <= 1440 then 'h. 1081-1440'
            when at.activ_loan = 0 and at.sleep_days <= 1800 then 'i. 1441-1800'
            else 'j. более 1800'
        end as sleep_days, -- Количество дней сна
        case
            when at.new_loan_after_end = 0 then 'Не было заявок после займа'
            when at.new_loan_after_end = 1 then 'a. 1 заявка после займа'
            when at.new_loan_after_end = 2 then 'b. 2 заявки после займа'
            when at.new_loan_after_end = 3 then 'c. 3 заявки после займа'
            when at.new_loan_after_end = 4 then 'd. 4 заявки после займа'
            when at.new_loan_after_end = 5 then 'e. 5 заявок после займа'
            else 'f. Более 5 заявок после займа'
        end as new_loan, -- заявки после последнего займа
                case
            when lim_prod_1 is null then 'Отсутствуют данные по лимитам'
            when lim_prod_1 <= 0 then 'Продукт не доступен клиенту'
            when lim_prod_1 <= 5000 then 'a. 0-5000'
            when lim_prod_1 <= 10000 then 'b. 5001-10000'
            when lim_prod_1 <= 15000 then 'c. 10001-15000'
            when lim_prod_1 <= 20000 then 'd. 15001-20000'
            when lim_prod_1 <= 25000 then 'e. 20001-25000'
            when lim_prod_1 <= 30000 then 'f. 25001-30000'
            else 'g. более 30000'
        end as lim_prod_1, -- Лимит по prod_1
        case
            when lim_prod_2 is null then 'Отсутствуют данные по лимитам'
            when lim_prod_2 <= 0 then 'Продукт не доступен клиенту'
            when lim_prod_2 <= 5000 then 'a. 0-5000'
            when lim_prod_2 <= 10000 then 'b. 5001-10000'
            when lim_prod_2 <= 15000 then 'c. 10001-15000'
            when lim_prod_2 <= 20000 then 'd. 15001-20000'
            when lim_prod_2 <= 25000 then 'e. 20001-25000'
            when lim_prod_2 <= 30000 then 'f. 25001-30000'
            when lim_prod_2 <= 35000 then 'g. 30001-35000'
            when lim_prod_2 <= 40000 then 'h. 35001-40000'
            when lim_prod_2 <= 45000 then 'i. 40001-45000'
            when lim_prod_2 <= 50000 then 'j. 45001-50000'
            else 'k. более 50000'
        end as lim_prod_2, -- Лимит по prod_2
        count(at.cl_id) as cl_id
    from all_table as at
    group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16;