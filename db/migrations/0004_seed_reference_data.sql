-- Wassalni / وصلني — reference data: categories, colours, colour adjacency.
-- Depends on 0001_init.sql.
--
-- This is reference data, not operational data: it ships with the schema and is
-- the same in every environment. Communities, districts and venues are seeded
-- per launch instead — see docs/SEEDING.md.

begin;

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------
-- group_key drives the partial-match score (15 points instead of 30). The
-- groups reflect how people actually misfile things: a phone gets reported
-- under "electronics" all the time, and a wallet is often inside the bag.

insert into categories (id, group_key, name_ar, name_en, icon_key, sort_order) values
  ('phone',       'tech',      'موبايل',            'Phone',        'smartphone',  10),
  ('wallet',      'carry',     'محفظة',             'Wallet',       'wallet',      20),
  ('keys',        'keys',      'مفاتيح',            'Keys',         'key',         30),
  ('bag',         'carry',     'شنطة',              'Bag',          'backpack',    40),
  ('documents',   'documents', 'أوراق ومستندات',    'Documents',    'description', 50),
  ('electronics', 'tech',      'إلكترونيات',        'Electronics',  'devices',     60),
  ('jewelry',     'valuables', 'مجوهرات وحاجة غالية','Jewelry',      'diamond',     70),
  ('other',       'other',     'حاجة تانية',        'Other',        'category',    80)
on conflict (id) do update set
  group_key = excluded.group_key,
  name_ar   = excluded.name_ar,
  name_en   = excluded.name_en,
  icon_key  = excluded.icon_key,
  sort_order = excluded.sort_order;

-- ---------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------
-- Deliberately coarse. People do not agree on "teal" versus "turquoise", and a
-- picker with 40 shades produces worse data than one with 16, because two
-- honest users describing the same object will pick different swatches.

insert into colors (id, name_ar, name_en, hex) values
  ('black',      'أسود',        'Black',      '#111111'),
  ('white',      'أبيض',        'White',      '#FFFFFF'),
  ('gray',       'رمادي',       'Gray',       '#8A8A8E'),
  ('silver',     'فضي',         'Silver',     '#C8CCD0'),
  ('brown',      'بني',         'Brown',      '#6B4423'),
  ('beige',      'بيچ',         'Beige',      '#D9C7A7'),
  ('gold',       'دهبي',        'Gold',       '#C9A227'),
  ('red',        'أحمر',        'Red',        '#C62828'),
  ('pink',       'وردي',        'Pink',       '#E91E8C'),
  ('orange',     'برتقالي',     'Orange',     '#EF6C00'),
  ('yellow',     'أصفر',        'Yellow',     '#F4C20D'),
  ('green',      'أخضر',        'Green',      '#2E7D32'),
  ('blue',       'أزرق',        'Blue',       '#1565C0'),
  ('navy',       'كحلي',        'Navy',       '#1A237E'),
  ('purple',     'بنفسجي',      'Purple',     '#6A1B9A'),
  ('multicolor', 'أكتر من لون', 'Multicolour','#7E7E7E')
on conflict (id) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  hex     = excluded.hex;

-- ---------------------------------------------------------------------------
-- Colour adjacency
-- ---------------------------------------------------------------------------
-- Two people describing the same object routinely disagree by one swatch —
-- "كحلي" versus "أزرق", "بيچ" versus "بني". Adjacency gives half credit for
-- that instead of dropping an otherwise strong match.
--
-- 'multicolor' is deliberately adjacent to nothing: it means "I can't say", and
-- treating it as similar to everything would make it a free 5 points on every
-- comparison.

insert into color_adjacency (color_id, adjacent_id)
select a, b from (
  select p.x as a, p.y as b from (values
    ('black','gray'), ('black','navy'),
    ('gray','silver'), ('gray','white'),
    ('silver','white'), ('silver','gold'),
    ('white','beige'),
    ('beige','brown'), ('beige','gold'),
    ('brown','gold'),
    ('gold','yellow'),
    ('yellow','orange'),
    ('orange','red'),
    ('red','pink'),
    ('pink','purple'),
    ('purple','navy'),
    ('navy','blue'),
    ('blue','green')
  ) as p(x, y)
  union all
  -- adjacency is symmetric; store both directions so the lookup needs no OR
  select p.y, p.x from (values
    ('black','gray'), ('black','navy'),
    ('gray','silver'), ('gray','white'),
    ('silver','white'), ('silver','gold'),
    ('white','beige'),
    ('beige','brown'), ('beige','gold'),
    ('brown','gold'),
    ('gold','yellow'),
    ('yellow','orange'),
    ('orange','red'),
    ('red','pink'),
    ('pink','purple'),
    ('purple','navy'),
    ('navy','blue'),
    ('blue','green')
  ) as p(x, y)
) as pairs(a, b)
on conflict do nothing;

commit;
