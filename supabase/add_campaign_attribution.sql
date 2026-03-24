begin;

-- campaigns = contexto operativo, no almacén de métricas
alter table public.campaigns
  add column if not exists starts_at timestamptz,
  add column if not exists ends_at timestamptz;

alter table public.visit_events
  add column if not exists campaign_id uuid;

alter table public.leads
  add column if not exists campaign_id uuid;

alter table public.form_submissions
  add column if not exists campaign_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'visit_events_campaign_id_fkey'
  ) then
    alter table public.visit_events
      add constraint visit_events_campaign_id_fkey
      foreign key (campaign_id) references public.campaigns(id)
      on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'leads_campaign_id_fkey'
  ) then
    alter table public.leads
      add constraint leads_campaign_id_fkey
      foreign key (campaign_id) references public.campaigns(id)
      on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'form_submissions_campaign_id_fkey'
  ) then
    alter table public.form_submissions
      add constraint form_submissions_campaign_id_fkey
      foreign key (campaign_id) references public.campaigns(id)
      on delete set null;
  end if;
end $$;

create index if not exists visit_events_campaign_id_idx
  on public.visit_events (campaign_id);

create index if not exists leads_campaign_id_idx
  on public.leads (campaign_id);

create index if not exists form_submissions_campaign_id_idx
  on public.form_submissions (campaign_id);

create unique index if not exists campaign_members_campaign_user_uidx
  on public.campaign_members (campaign_id, user_id);

create index if not exists campaign_members_campaign_id_idx
  on public.campaign_members (campaign_id);

create index if not exists campaign_members_user_id_idx
  on public.campaign_members (user_id);

-- campaña activa para una tarjeta en un momento dado
create or replace function public.get_active_campaign_for_card(
  p_card_id uuid,
  p_at timestamptz default now()
)
returns uuid
language sql
stable
as $$
  select c.id
  from public.digital_cards dc
  join public.campaign_members cm
    on cm.user_id = dc.user_id
  join public.campaigns c
    on c.id = cm.campaign_id
  where dc.id = p_card_id
    and c.starts_at is not null
    and c.ends_at is not null
    and p_at >= c.starts_at
    and p_at < c.ends_at
  order by c.starts_at desc
  limit 1
$$;

-- registro de visita/interacción con campaña automática
drop function if exists public.record_card_visit(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text
);

create or replace function public.record_card_visit(
  p_card_id uuid,
  p_source text,
  p_label text default null,
  p_device text default null,
  p_ip text default null,
  p_city text default null,
  p_country text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign_id uuid;
  v_event_id uuid;
begin
  v_campaign_id := public.get_active_campaign_for_card(p_card_id, now());

  insert into public.visit_events (
    card_id,
    campaign_id,
    "timestamp",
    ip,
    device,
    city,
    country,
    source,
    label
  )
  values (
    p_card_id,
    v_campaign_id,
    now(),
    p_ip,
    p_device,
    p_city,
    p_country,
    p_source,
    p_label
  )
  returning id into v_event_id;

  return v_event_id;
end;
$$;

-- click de enlace: mantiene aggregate y también registra evento atribuible
drop function if exists public.record_link_click(
  uuid,
  uuid,
  text,
  text
);

create or replace function public.record_link_click(
  p_id uuid,
  p_card_id uuid,
  p_label text,
  p_platform text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_campaign_id uuid;
begin
  insert into public.link_stats (
    card_id,
    link_ref_id,
    label,
    platform,
    clicks,
    updated_at
  )
  values (
    p_card_id,
    p_id,
    p_label,
    p_platform,
    1,
    v_now
  )
  on conflict do nothing;

  update public.link_stats
  set clicks = coalesce(clicks, 0) + 1,
      updated_at = v_now
  where card_id = p_card_id
    and link_ref_id = p_id;

  v_campaign_id := public.get_active_campaign_for_card(p_card_id, v_now);

  insert into public.visit_events (
    card_id,
    campaign_id,
    "timestamp",
    source,
    label
  )
  values (
    p_card_id,
    v_campaign_id,
    v_now,
    'link',
    coalesce(p_label, p_platform)
  );
end;
$$;

-- lead y submission con campaign_id automático
drop function if exists public.submit_card_form(
  uuid,
  text,
  text,
  text,
  text,
  text,
  jsonb
);

create or replace function public.submit_card_form(
  p_card_id uuid,
  p_form_type text,
  p_name text,
  p_email text default null,
  p_phone text default null,
  p_company text default null,
  p_form_data jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign_id uuid;
  v_org_id uuid;
  v_form_id uuid;
  v_lead_id uuid;
begin
  select dc.org_id
    into v_org_id
  from public.digital_cards dc
  where dc.id = p_card_id;

  v_campaign_id := public.get_active_campaign_for_card(p_card_id, now());

  insert into public.leads (
    card_id,
    org_id,
    campaign_id,
    name,
    company,
    first_seen,
    last_seen,
    pipeline_stage,
    form_data,
    form_type
  )
  values (
    p_card_id,
    v_org_id,
    v_campaign_id,
    p_name,
    p_company,
    now(),
    now(),
    'newLead',
    coalesce(p_form_data, '{}'::jsonb) ||
      jsonb_build_object(
        'email', p_email,
        'phone', p_phone
      ),
    p_form_type
  )
  returning id into v_lead_id;

  select sf.id
    into v_form_id
  from public.smart_forms sf
  where sf.card_id = p_card_id
    and lower(sf.name) = lower(p_form_type)
  order by sf.created_at desc
  limit 1;

  insert into public.form_submissions (
    form_id,
    lead_id,
    campaign_id,
    data,
    submitted_at
  )
  values (
    v_form_id,
    v_lead_id,
    v_campaign_id,
    coalesce(p_form_data, '{}'::jsonb),
    now()
  );

  insert into public.visit_events (
    card_id,
    campaign_id,
    "timestamp",
    source,
    label
  )
  values (
    p_card_id,
    v_campaign_id,
    now(),
    'form',
    p_form_type
  );

  return v_lead_id;
end;
$$;

-- RLS mínimo para campañas y miembros
alter table public.campaigns enable row level security;
alter table public.campaign_members enable row level security;

drop policy if exists campaigns_select_same_org on public.campaigns;
drop policy if exists campaigns_insert_same_org on public.campaigns;
drop policy if exists campaigns_update_same_org on public.campaigns;
drop policy if exists campaigns_delete_same_org on public.campaigns;

create policy campaigns_select_same_org
on public.campaigns
for select
to authenticated
using (
  org_id in (
    select u.org_id
    from public.users u
    where u.id = auth.uid()
  )
);

create policy campaigns_insert_same_org
on public.campaigns
for insert
to authenticated
with check (
  org_id in (
    select u.org_id
    from public.users u
    where u.id = auth.uid()
  )
);

create policy campaigns_update_same_org
on public.campaigns
for update
to authenticated
using (
  org_id in (
    select u.org_id
    from public.users u
    where u.id = auth.uid()
  )
)
with check (
  org_id in (
    select u.org_id
    from public.users u
    where u.id = auth.uid()
  )
);

create policy campaigns_delete_same_org
on public.campaigns
for delete
to authenticated
using (
  org_id in (
    select u.org_id
    from public.users u
    where u.id = auth.uid()
  )
);

drop policy if exists campaign_members_select_same_org on public.campaign_members;
drop policy if exists campaign_members_insert_same_org on public.campaign_members;
drop policy if exists campaign_members_update_same_org on public.campaign_members;
drop policy if exists campaign_members_delete_same_org on public.campaign_members;

create policy campaign_members_select_same_org
on public.campaign_members
for select
to authenticated
using (
  exists (
    select 1
    from public.campaigns c
    join public.users u on u.org_id = c.org_id
    where c.id = campaign_members.campaign_id
      and u.id = auth.uid()
  )
);

create policy campaign_members_insert_same_org
on public.campaign_members
for insert
to authenticated
with check (
  exists (
    select 1
    from public.campaigns c
    join public.users u on u.org_id = c.org_id
    where c.id = campaign_members.campaign_id
      and u.id = auth.uid()
  )
);

create policy campaign_members_update_same_org
on public.campaign_members
for update
to authenticated
using (
  exists (
    select 1
    from public.campaigns c
    join public.users u on u.org_id = c.org_id
    where c.id = campaign_members.campaign_id
      and u.id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.campaigns c
    join public.users u on u.org_id = c.org_id
    where c.id = campaign_members.campaign_id
      and u.id = auth.uid()
  )
);

create policy campaign_members_delete_same_org
on public.campaign_members
for delete
to authenticated
using (
  exists (
    select 1
    from public.campaigns c
    join public.users u on u.org_id = c.org_id
    where c.id = campaign_members.campaign_id
      and u.id = auth.uid()
  )
);

alter table public.campaigns
  drop column if exists status,
  drop column if exists taps,
  drop column if exists leads,
  drop column if exists conversions;

commit;
