-- MAYOR: como paga cada cliente (27/11/2026, pedido de Kelvin).
-- La 2da linea de un pedido que se pasa a un grupo de pais dice "RST" (paga con retiro sin tarjeta) o "CUENTA" (transferencia o
-- deposito), y de eso depende el precio. El bot la saca por la tasa que uso el cliente; si el pedido trae un solo monto, usa esta
-- columna, y si esta vacia, lo que la operadora le pone siempre a ese cliente en los grupos de paises.
-- Kelvin la puede llenar o cambiar a mano en Table Editor: rst, cuenta o vacio.
-- (El llenado inicial con los clientes de verdad esta en sql/privado/mayor_forma_pago_inicial.sql, que no se sube a GitHub.)
alter table public.grupos_mayor add column if not exists forma_pago text check (forma_pago in ('rst', 'cuenta'));
comment on column public.grupos_mayor.forma_pago is 'Como paga siempre el cliente del mayor: rst (retiro sin tarjeta) o cuenta (transferencia/deposito). Decide la 2da linea del pedido y el precio.';
