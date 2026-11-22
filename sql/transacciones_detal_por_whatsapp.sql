-- ============================================================================
--  Tabla transacciones_detal_por_whatsapp: el registro de cada operacion que llega
--  por el bot de WhatsApp. UNA FILA POR CUENTA DESTINO: cada cuenta tiene su propio
--  estado y pasa a 'enviada' cuando la operadora devuelve la foto de ESA cuenta.
--  Las cuentas de un mismo deposito comparten id_msg_captura.
--
--  Es APARTE de la tabla "transacciones" de la app, que no se toca.
--  Se corrio en Supabase -> SQL Editor el 20/11/2026.
--  Solo el esquema: aqui nunca van datos de clientes (el repositorio es publico).
--
--  Estados:
--    pendiente  : falta la cuenta destino o la captura del deposito
--    en_espera  : completa, pero llego fuera de horario; la publica al abrir el
--                 workflow "Liberar operaciones de la noche" (9:05; domingo 10:05)
--    en_proceso : publicada en el grupo de transferir
--    enviada    : la operadora devolvio la foto del envio y le llego al cliente
--    repetida   : la captura era de un deposito que ya se habia recibido
--    cancelada
-- ============================================================================

create table if not exists public.transacciones_detal_por_whatsapp (
  id               bigint generated always as identity primary key,
  creado           timestamptz not null default now(),
  actualizado      timestamptz not null default now(),
  whatsapp         text        not null,                 -- solo digitos, ej. 593900000000
  nombre_cliente   text,
  estado           text        not null default 'pendiente'
                   check (estado in ('pendiente','en_espera','en_proceso','enviada','repetida','cancelada')),
  monto_deposito   numeric(14,2),
  ref_deposito     text,
  banco_origen     text,
  huella_foto      text,
  id_msg_captura   text,
  capturas         jsonb       not null default '[]'::jsonb,   -- una o varias pantallas del pago
  cuentas          jsonb       not null default '[]'::jsonb,   -- una o varias cuentas destino, cada una con su monto
  id_msgs_grupo    jsonb       not null default '[]'::jsonb,   -- lo publicado en transferir
  fuera_de_horario boolean     not null default false,
  publicado_en     timestamptz,
  enviada_en       timestamptz,
  notas            text
);

comment on column public.transacciones_detal_por_whatsapp.estado is
  'pendiente: falta cuenta o captura | en_espera: completa fuera de horario, se publica al abrir | en_proceso: publicada en transferir | enviada: la operadora devolvio la foto | repetida | cancelada';

create index if not exists tpw_whatsapp_idx  on public.transacciones_detal_por_whatsapp (whatsapp, creado desc);
create index if not exists tpw_en_espera_idx on public.transacciones_detal_por_whatsapp (creado) where estado = 'en_espera';

create or replace function public.tpw_tocar_actualizado() returns trigger
language plpgsql set search_path = public as $$
begin
  new.actualizado := now();
  return new;
end;
$$;

drop trigger if exists tpw_actualizado on public.transacciones_detal_por_whatsapp;
create trigger tpw_actualizado before update on public.transacciones_detal_por_whatsapp
  for each row execute function public.tpw_tocar_actualizado();

-- Seguridad: RLS prendido y SIN politicas. La clave publica de la app no ve nada;
-- el bot entra con la clave de servicio (credencial "Supabase Cambios JK" de n8n).
alter table public.transacciones_detal_por_whatsapp enable row level security;
-- Nota 22/11: la tabla se renombro con:  alter table public.transacciones_por_whatsapp rename to transacciones_detal_por_whatsapp;
