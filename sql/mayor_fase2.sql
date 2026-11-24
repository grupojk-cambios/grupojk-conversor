-- ============================================================================
--  MAYOR, FASE 2: el bot publica los RST / RCT en los grupos de los bancos.
--  Se corre una vez en Supabase -> SQL Editor (despues de sql/mayor_fase1.sql).
--
--  Solo el esquema: aqui nunca van datos de clientes ni de grupos (el repositorio es publico).
--  Los grupos nuevos (COBRAR MAÑANA, los bancos...) se cargan aparte con sql/privado/.
--  Si lo corres dos veces no pasa nada.
-- ============================================================================

-- Por grupo de cliente: ¿el bot puede PUBLICAR de verdad en los bancos? Por defecto NO (queda en ensayo:
-- solo vistas previas en el grupo de avisos). Se enciende grupo por grupo cuando Kelvin lo decida:
--   update public.grupos_mayor set publicar = true where nombre = 'NOMBRE DEL GRUPO';
-- Ademas el workflow tiene que estar en modo real ($MAYOR_MODO en mayor_comun.ps1).
alter table public.grupos_mayor add column if not exists publicar boolean not null default false;

comment on column public.grupos_mayor.publicar is
  'true = el bot publica de verdad los RST/RCT de este grupo en los grupos de los bancos (con el workflow en modo real). false = solo ensayo.';

-- A que grupo se publico cada mensaje (PICHINCHA, COBRAR MAÑANA...).
alter table public.transacciones_mayor_por_whatsapp add column if not exists grupo_destino text;

comment on column public.transacciones_mayor_por_whatsapp.estado is
  'visto: solo registrado. Fase 2: ensayo, publicado, en_cobrar_manana (espera al banco al abrir), cobrar_hoy (se queda en COBRAR MAÑANA), falta_datos, pide_texto, sin_grupo, verificar, danado, vencido, error_envio.';

-- ============================================================================
--  ALERTAS DE VENCIMIENTO (protocolo_rst_rct.md, seccion 7)
--  Cada RST que esta en el grupo de un banco se anota aqui con la hora en que vence. Si cuando falta 1 hora
--  (o 6 minutos en JEP) nadie lo marco como cobrado (con una reaccion), el bot cita el mensaje en el grupo y avisa.
--  Solo se anotan los bancos que el manual dice cuanto duran: Pichincha, Pacifico, Guayaquil, Produbanco,
--  Bolivariano y JEP. Si la corres dos veces no pasa nada.
-- ============================================================================
create table if not exists public.vigilancia_rst_mayor (
  id                 bigint      generated always as identity primary key,
  creado             timestamptz not null default now(),
  banco              text        not null,                          -- pichincha, pacifico, guayaquil, produbanco, bolivariano, jep
  grupo_jid          text        not null,                          -- el grupo donde esta el mensaje del RST (el del banco)
  mensaje_id         text        not null,                          -- id de ese mensaje en WhatsApp
  resumen            text,                                          -- "Nombre - BANCO 100$": para avisar si la cita no funciona
  recibido_en        timestamptz not null,                          -- cuando llego el codigo (el reloj del banco corre desde aqui)
  vence_en           timestamptz not null,
  alerta_en          timestamptz not null,                          -- desde cuando se puede avisar
  origen             text        not null default 'manual' check (origen in ('manual', 'bot')),
  cobro              text        not null default 'pendiente'
                     check (cobro in ('pendiente', 'cobrado', 'no_cobrado', 'verificar', 'danado', 'vencido')),
  cobro_en           timestamptz,
  cobro_emoji        text,
  alerta_enviada_en  timestamptz,
  alerta_resultado   text,                                          -- enviada, ensayo, error, vencido, sin_grupo
  unique (grupo_jid, mensaje_id)
);

comment on table public.vigilancia_rst_mayor is
  'RST publicados en los grupos de los bancos, vigilados para avisar antes de que venzan (si nadie los marco como cobrados).';
comment on column public.vigilancia_rst_mayor.cobro is
  'pendiente: sin reaccion. cobrado: cualquier emoji menos la X. no_cobrado: reaccion con X. verificar / danado: el banco pidio corregirlo (ya viene uno nuevo). vencido: se paso la hora.';

create index if not exists vrm_alerta_idx on public.vigilancia_rst_mayor (alerta_en) where alerta_enviada_en is null;

alter table public.vigilancia_rst_mayor enable row level security;
