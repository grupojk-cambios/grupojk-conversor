-- 1. Crear la tabla de transacciones
create table public.transacciones (
  id uuid default gen_random_uuid() primary key,
  codigo text not null unique,
  fecha timestamp with time zone default timezone('utc'::text, now()) not null,
  nombre_cliente text not null,
  apellido_cliente text not null,
  whatsapp_cliente text not null,
  pais_origen text not null,
  moneda_origen text not null,
  monto_enviado numeric not null,
  pais_destino text not null,
  moneda_destino text not null,
  monto_recibir numeric not null,
  tasa_pactada numeric not null,
  estado text not null default 'Pendiente' check (estado in ('Pendiente', 'Verificando', 'Completada', 'Cancelada')),
  tipo_cliente text not null default 'Estándar' check (tipo_cliente in ('Estándar', 'Mayorista'))
);

-- 2. Configurar la seguridad (RLS - Row Level Security)
-- Habilitar RLS en la tabla
alter table public.transacciones enable row level security;

-- Política 1: Permitir a cualquier usuario (incluso anónimos de la web) insertar datos
create policy "Permitir insertar cotizaciones desde la web"
on public.transacciones for insert
to public
with check (true);

-- Política 2: Permitir la lectura a todos los usuarios (para que funcione el panel de administración temporalmente sin auth)
create policy "Permitir leer transacciones"
on public.transacciones for select
to public
using (true);

-- Política 3: Permitir actualizar el estado de las transacciones (para el panel de administrador)
create policy "Permitir actualizar transacciones"
on public.transacciones for update
to public
using (true);

-- 3. Tabla de Perfiles (Sincronizada con Auth)
create table if not exists public.perfiles (
  id uuid references auth.users on delete cascade not null primary key,
  full_name text,
  avatar_url text,
  whatsapp text,
  role text default 'cliente',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.perfiles enable row level security;

create policy "Los usuarios pueden ver su propio perfil" on public.perfiles
  for select using (auth.uid() = id);

create policy "Los usuarios pueden actualizar su propio perfil" on public.perfiles
  for update using (auth.uid() = id);

-- 4. Función y Trigger para creación automática de perfiles
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.perfiles (id, full_name, avatar_url, whatsapp)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nombre', new.raw_user_meta_data->>'full_name'),
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'whatsapp'
  );
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
