-- ============================================================================
--  QUITAR LA TABLA clientes_bot_mayor  (26/11/2026)
--  Se corre UNA vez en Supabase -> SQL Editor.
--
--  Por que: el mayor se atiende por sus GRUPOS de WhatsApp (tabla grupos_mayor), no por
--  el chat privado del bot. Desde el 26/11 el bot ya no lee esta tabla (ni perfiles_mayor
--  para dejar pasar a nadie), asi que quedo sin uso.
--
--  Seguro: si la tabla tiene alguna fila, NO la borra y avisa. Asi no se pierde nada
--  que se haya cargado sin querer.
--
--  Los grupos del mayor se siguen anotando en grupos_mayor (Table Editor -> Insert).
-- ============================================================================

do $$
declare
  filas bigint;
begin
  if to_regclass('public.clientes_bot_mayor') is null then
    raise notice 'La tabla clientes_bot_mayor ya no existe. No hay nada que hacer.';
    return;
  end if;

  execute 'select count(*) from public.clientes_bot_mayor' into filas;
  if filas > 0 then
    raise exception 'NO se borro: clientes_bot_mayor tiene % fila(s). Revisalas primero.', filas;
  end if;

  drop table public.clientes_bot_mayor;
  raise notice 'Listo: clientes_bot_mayor borrada (estaba vacia).';
end
$$;
