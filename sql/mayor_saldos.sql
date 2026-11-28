-- MAYOR: SALDO DE CADA CLIENTE (27/11/2026, pedido de Kelvin). Se corre UNA vez en Supabase (SQL Editor).
--
-- Cada cosa que mueve plata de un cliente del mayor queda aqui como un MOVIMIENTO:
--   pago    -> lo que pago: un RST/RCT completo (cuenta apenas llega, Kelvin 27/11) o la foto de su pago leida con IA
--   pedido  -> lo que pidio, en dolares (Binance/Zelle: lo cobrado; los demas paises: el $ del pedido, o los Bs / la tasa)
--   ajuste  -> lo que Kelvin anota a mano: un saldo de antes (+ a favor del cliente, - lo que debe), una correccion...
-- El saldo = pagos + ajustes - pedidos. Hay dos: el del DIA (con eso el bot decide si un pedido pasa o espera su pago) y el
-- CORRIDO (todo junto, para llevar la cuenta). Mientras el mayor este en ENSAYO, el bot solo lo muestra en el grupo de avisos.
--
-- Para anotar un saldo de antes: Table Editor -> movimientos_mayor -> Insert: grupo_jid (el del grupo del cliente), tipo = ajuste,
-- monto_usd (positivo si tiene a favor, negativo si debe), detalle (ej. "saldo inicial"), origen = manual. Lo demas se llena solo.

create table if not exists public.movimientos_mayor (
  id            bigserial primary key,
  creado        timestamptz not null default now(),
  grupo_jid     text        not null,
  cliente_nombre text,
  fecha         timestamptz not null default now(),          -- hora del mensaje de WhatsApp
  dia           date        not null default ((now() at time zone 'America/Guayaquil')::date),   -- el dia en Ecuador (saldo diario)
  tipo          text        not null check (tipo in ('pago', 'pedido', 'ajuste')),
  forma         text        check (forma in ('rst', 'cuenta')),   -- pago: como pago; pedido: a que precio se calculo
  monto_usd     numeric(12, 2) not null,                    -- pago/pedido: siempre positivo; ajuste: + a favor / - debe
  detalle       text,                                       -- 'RST Pichincha', 'foto: Banco Pichincha ref 123', 'BINANCE 150 -> 145.50'...
  mensaje_id    text,                                       -- el mensaje de WhatsApp de donde salio
  clave         text        unique,                         -- mensaje_id + numero: para no contar dos veces lo mismo
  estado        text        not null default 'ok' check (estado in ('ok', 'anulado')),   -- anulado = no cuenta (ej. un RST que se daño)
  origen        text        not null default 'bot' check (origen in ('bot', 'manual'))
);
create index if not exists movimientos_mayor_grupo_dia_idx on public.movimientos_mayor (grupo_jid, dia);

comment on table public.movimientos_mayor is 'Pagos, pedidos y ajustes de cada cliente del mayor. Saldo = pagos + ajustes - pedidos (por dia y corrido).';

-- Lo que lee el bot: por cliente, el saldo CORRIDO y la lista de los movimientos de HOY (en orden). Una sola consulta.
create or replace view public.saldo_mayor as
select grupo_jid,
       coalesce(sum(case when tipo = 'pedido' then -monto_usd else monto_usd end) filter (where estado = 'ok'), 0)::numeric(12, 2) as saldo_corrido,
       coalesce(jsonb_agg(jsonb_build_object('id', id, 'fecha', fecha, 'tipo', tipo, 'forma', forma, 'monto_usd', monto_usd, 'detalle', detalle, 'mensaje_id', mensaje_id)
                          order by fecha, id)
                filter (where estado = 'ok' and dia = (now() at time zone 'America/Guayaquil')::date), '[]'::jsonb) as hoy
from public.movimientos_mayor
group by grupo_jid;

-- Para mirar en Supabase el saldo de cada dia de cada cliente (Table Editor -> saldo_mayor_diario).
create or replace view public.saldo_mayor_diario as
select grupo_jid, max(cliente_nombre) as cliente_nombre, dia,
       coalesce(sum(monto_usd) filter (where tipo = 'pago' and estado = 'ok'), 0)::numeric(12, 2)   as pagado,
       coalesce(sum(monto_usd) filter (where tipo = 'pedido' and estado = 'ok'), 0)::numeric(12, 2) as pedido,
       coalesce(sum(monto_usd) filter (where tipo = 'ajuste' and estado = 'ok'), 0)::numeric(12, 2) as ajustes,
       coalesce(sum(case when tipo = 'pedido' then -monto_usd else monto_usd end) filter (where estado = 'ok'), 0)::numeric(12, 2) as saldo_del_dia
from public.movimientos_mayor
group by grupo_jid, dia;

-- La tabla solo la usa el bot con su llave de servicio (igual que transacciones_mayor_por_whatsapp).
alter table public.movimientos_mayor enable row level security;
