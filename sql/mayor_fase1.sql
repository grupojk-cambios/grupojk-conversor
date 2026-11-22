-- ============================================================================
--  MAYOR, FASE 1: el bot escucha y registra los grupos de clientes mayoristas.
--  Se corre una vez en Supabase -> SQL Editor.
--
--  Solo el esquema: aqui nunca van datos de clientes ni de grupos (el repositorio es
--  publico). Los grupos de prueba se cargan aparte, con un INSERT que se corre a mano.
--
--  Las dos tablas llevan RLS prendido y SIN politicas: la clave publica de la app no
--  ve nada; el bot entra con la clave de servicio (credencial "Supabase Cambios JK").
-- ============================================================================

-- Los grupos que el bot escucha. Un grupo que no este aqui, el bot lo ignora como siempre.
create table if not exists public.grupos_mayor (
  grupo_jid                text        primary key,                 -- ej. 120363000000000000@g.us
  nombre                   text        not null,
  tipo                     text        not null default 'cliente'
                           check (tipo in ('cliente', 'tasas', 'destino')),  -- tasas = VENTAS MAYOR; destino = abonos, RST, bancos, paises
  cliente_whatsapp         text,                                    -- solo digitos, con codigo de pais
  operador_extra_whatsapp  text,                                    -- el operador extra del cliente, si tiene
  operadora_whatsapp       text,                                    -- "Atencion al cliente": con ella (y con Kelvin) el bot calla
  activo                   boolean     not null default true,
  creado                   timestamptz not null default now()
);

-- Si la tabla ya existia con solo 'cliente' y 'tasas' (22/11), se amplia asi:
--   alter table public.grupos_mayor drop constraint if exists grupos_mayor_tipo_check;
--   alter table public.grupos_mayor add constraint grupos_mayor_tipo_check check (tipo in ('cliente', 'tasas', 'destino'));

comment on table public.grupos_mayor is
  'Grupos de WhatsApp que el bot escucha (mayor). Fase 1: solo registra, no responde.';

-- Lo que el bot entendio de cada mensaje. Una fila por mensaje (mensaje_id es unico: los mensajes
-- de grupo a veces llegan duplicados).
create table if not exists public.transacciones_mayor_por_whatsapp (
  id               bigint generated always as identity primary key,
  creado           timestamptz not null default now(),
  actualizado      timestamptz not null default now(),
  mensaje_id       text        not null unique,
  fecha_mensaje    timestamptz,                                    -- cuando se escribio el mensaje en WhatsApp
  grupo_jid        text        not null,
  cliente_nombre   text,
  autor_rol        text        not null default 'otro'
                   check (autor_rol in ('cliente', 'operador_extra', 'kelvin', 'operadora', 'otro')),
  autor_numero     text,                                           -- solo digitos
  tipo             text        not null default 'otro'
                   check (tipo in ('beneficiario', 'rst', 'rct', 'mixto', 'captura', 'pregunta', 'tasas', 'audio', 'otro')),
  pais             text,                                           -- null = no se pudo saber; el bot nunca lo asume
  banco            text,
  monto_usd        numeric(14,2),
  monto_local      numeric(18,2),
  moneda           text,
  datos            jsonb       not null default '{}'::jsonb,       -- registros entendidos: cuenta, cedula, clave, telefono...
  texto            text,
  estado           text        not null default 'visto'
);

comment on column public.transacciones_mayor_por_whatsapp.estado is
  'visto: el bot lo registro y no hizo nada mas (Fase 1). Las fases siguientes lo llevan a publicado, enviado, etc.';

create index if not exists tmw_grupo_idx on public.transacciones_mayor_por_whatsapp (grupo_jid, creado desc);
create index if not exists tmw_tipo_idx  on public.transacciones_mayor_por_whatsapp (tipo, creado desc);

create or replace function public.tmw_tocar_actualizado() returns trigger
language plpgsql set search_path = public as $$
begin
  new.actualizado := now();
  return new;
end;
$$;

drop trigger if exists tmw_actualizado on public.transacciones_mayor_por_whatsapp;
create trigger tmw_actualizado before update on public.transacciones_mayor_por_whatsapp
  for each row execute function public.tmw_tocar_actualizado();

alter table public.grupos_mayor enable row level security;
alter table public.transacciones_mayor_por_whatsapp enable row level security;
