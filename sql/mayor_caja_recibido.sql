-- MAYOR: "RECIBIDO" DEL CORTE DE UN COBRADOR (27/11/2026, pedido de Kelvin). Se corre UNA vez en Supabase (SQL Editor), DESPUES de
-- sql/mayor_caja_cobradores.sql y ANTES de desplegar la version del bot que lo usa.
--
-- Cuando el cobrador entrega el efectivo, Kelvin o la operadora responden en el grupo del banco CITANDO su mensaje "corte hasta
-- aqui" con "recibido 4100" (o solo "recibido" si entrego justo el total del corte). El bot anota la entrega en
-- entregas_cobradores a nombre de ese cobrador y dice cuanto queda debiendo.

-- Quienes pueden confirmar un "recibido" en los grupos de los bancos, ademas de Kelvin y la operadora: numeros separados por coma
-- (los numeros reales van en sql/privado/mayor_operadores_caja.sql, que no se sube a GitHub).
alter table public.grupos_mayor add column if not exists operadores_caja text;
comment on column public.grupos_mayor.operadores_caja is 'Grupos de banco: numeros (separados por coma) que pueden confirmar con "recibido" la entrega del corte de un cobrador.';

-- La entrega guarda el mensaje del "recibido": un mismo mensaje no se anota dos veces.
alter table public.entregas_cobradores add column if not exists mensaje_id text;
create unique index if not exists entregas_cobradores_mensaje_idx on public.entregas_cobradores (mensaje_id);

-- Lo que consulta el bot ("Corte del Cobrador"), en UNA sola vista con una "clave":
--   'cobrador:<numero>'  -> lo que ese cobrador cobro desde su ultimo corte (para contestarle el corte)
--   'corte:<mensaje>'    -> el corte que se cito con "recibido": de quien es, cuanto era y cuanto debe hoy ese cobrador
create or replace view public.caja_consulta as
select 'cobrador:' || p.cobrador        as clave,
       p.cobrador, p.cobrador_nombre, p.n_rst, p.total_usd, p.ultimo_corte,
       null::timestamptz                as hasta,
       c.debe_entregar
from public.corte_pendiente p
left join public.caja_cobradores c on c.cobrador = p.cobrador
union all
select 'corte:' || k.mensaje_id         as clave,
       k.cobrador, k.cobrador_nombre, k.n_rst, k.total_usd,
       null::timestamptz                as ultimo_corte,
       k.hasta,
       c.debe_entregar
from public.cortes_cobradores k
left join public.caja_cobradores c on c.cobrador = k.cobrador
where k.mensaje_id is not null;
