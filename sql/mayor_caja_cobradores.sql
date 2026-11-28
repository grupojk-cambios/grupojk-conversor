-- MAYOR: LA CAJA DE LOS BANCOS Y DE CADA COBRADOR (27/11/2026, pedido de Kelvin). Se corre UNA vez en Supabase (SQL Editor),
-- ANTES de desplegar la version del bot que la usa (el bot empieza a guardar quien marco cada RST como cobrado).
--
-- Los RST que se pegan en los grupos de los bancos ya quedan en vigilancia_rst_mayor (los de las alertas), y la reaccion del
-- cobrador (✅, 👍, 💵...) ya los marca "cobrado". Aqui se agrega QUIEN lo marco, y con eso:
--   caja_bancos_diario -> por banco y por dia: cuantos RST llegaron, cuanto se cobro, lo pendiente, lo dañado y lo vencido.
--   caja_cobradores    -> por cobrador: lo que cobro, lo que entrego (Kelvin lo anota en entregas_cobradores) y lo que debe.
--   corte_pendiente    -> por cobrador: lo que cobro desde su ultimo "corte hasta aqui" (el bot se lo contesta).
-- (Varios cobradores pueden estar en un mismo grupo: la cuenta va por la PERSONA que marco el RST. No hay comision: entrega todo.)
--
-- Para anotar una entrega en efectivo: Table Editor -> entregas_cobradores -> Insert: cobrador (el numero, como sale en
-- caja_cobradores), monto_usd, nota. La fecha se llena sola.

alter table public.vigilancia_rst_mayor add column if not exists cobrado_por text;          -- numero de WhatsApp de quien lo marco cobrado
alter table public.vigilancia_rst_mayor add column if not exists cobrado_por_nombre text;   -- su nombre en WhatsApp

-- El monto de cada RST sale de su resumen ("PICHINCHA 100$", "Cliente · GUAYAQUIL 250.50$").
create or replace function public.monto_de_resumen(t text) returns numeric language sql immutable as $$
  select nullif(substring(coalesce(t, '') from '([0-9]+(?:\.[0-9]+)?)\s*\$'), '')::numeric
$$;

create table if not exists public.entregas_cobradores (
  id              bigserial   primary key,
  creado          timestamptz not null default now(),
  fecha           timestamptz not null default now(),
  cobrador        text        not null,             -- el numero del cobrador (como sale en caja_cobradores)
  cobrador_nombre text,
  monto_usd       numeric(12, 2) not null,          -- lo que entrego en efectivo
  nota            text
);

create table if not exists public.cortes_cobradores (
  id              bigserial   primary key,
  creado          timestamptz not null default now(),
  hasta           timestamptz not null,             -- la hora del mensaje "corte hasta aqui"
  cobrador        text        not null,
  cobrador_nombre text,
  grupo_jid       text,                             -- el grupo del banco donde lo pidio
  n_rst           integer,
  total_usd       numeric(12, 2),
  mensaje_id      text        unique                -- el mensaje del corte (no se cuenta dos veces)
);
create index if not exists cortes_cobradores_cobrador_idx on public.cortes_cobradores (cobrador, hasta desc);

create or replace view public.caja_bancos_diario as
select banco,
       (recibido_en at time zone 'America/Guayaquil')::date as dia,
       count(*)                                                                   as rst,
       coalesce(sum(m), 0)::numeric(12, 2)                                        as monto_total,
       count(*) filter (where cobro = 'cobrado')                                  as cobrados,
       coalesce(sum(m) filter (where cobro = 'cobrado'), 0)::numeric(12, 2)       as monto_cobrado,
       count(*) filter (where cobro = 'pendiente')                                as pendientes,
       coalesce(sum(m) filter (where cobro = 'pendiente'), 0)::numeric(12, 2)     as monto_pendiente,
       count(*) filter (where cobro in ('no_cobrado', 'verificar', 'danado'))     as con_problema,
       coalesce(sum(m) filter (where cobro in ('no_cobrado', 'verificar', 'danado')), 0)::numeric(12, 2) as monto_con_problema,
       count(*) filter (where cobro = 'vencido')                                  as vencidos,
       coalesce(sum(m) filter (where cobro = 'vencido'), 0)::numeric(12, 2)       as monto_vencido
from (select v.*, public.monto_de_resumen(v.resumen) as m from public.vigilancia_rst_mayor v) x
group by banco, (recibido_en at time zone 'America/Guayaquil')::date;

create or replace view public.corte_pendiente as
select v.cobrado_por                                   as cobrador,
       max(v.cobrado_por_nombre)                       as cobrador_nombre,
       count(*)                                        as n_rst,
       coalesce(sum(public.monto_de_resumen(v.resumen)), 0)::numeric(12, 2) as total_usd,
       min(v.cobro_en)                                 as desde,
       k.ultimo                                        as ultimo_corte
from public.vigilancia_rst_mayor v
left join (select cobrador, max(hasta) as ultimo from public.cortes_cobradores group by cobrador) k on k.cobrador = v.cobrado_por
where v.cobro = 'cobrado' and v.cobrado_por is not null and v.cobrado_por <> '' and (k.ultimo is null or v.cobro_en > k.ultimo)
group by v.cobrado_por, k.ultimo;

create or replace view public.caja_cobradores as
with cobros as (
  select cobrado_por as cobrador, max(cobrado_por_nombre) as nombre, count(*) as rst, sum(public.monto_de_resumen(resumen)) as total
  from public.vigilancia_rst_mayor
  where cobro = 'cobrado' and cobrado_por is not null and cobrado_por <> ''
  group by cobrado_por),
entregas as (select cobrador, max(cobrador_nombre) as nombre, sum(monto_usd) as total from public.entregas_cobradores group by cobrador),
cortes as (select cobrador, max(hasta) as ultimo from public.cortes_cobradores group by cobrador)
select coalesce(c.cobrador, e.cobrador)                                  as cobrador,
       coalesce(c.nombre, e.nombre)                                      as cobrador_nombre,
       coalesce(c.rst, 0)                                                as rst_cobrados,
       coalesce(c.total, 0)::numeric(12, 2)                              as cobrado,
       coalesce(e.total, 0)::numeric(12, 2)                              as entregado,
       (coalesce(c.total, 0) - coalesce(e.total, 0))::numeric(12, 2)     as debe_entregar,
       k.ultimo                                                          as ultimo_corte
from cobros c
full join entregas e on e.cobrador = c.cobrador
left join cortes k on k.cobrador = coalesce(c.cobrador, e.cobrador);

alter table public.entregas_cobradores enable row level security;
alter table public.cortes_cobradores enable row level security;
