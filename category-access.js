/* HUB DE MIIANA - accès aux catégories selon le rôle Supabase */
(function () {
  const config = window.SUPABASE_CONFIG;
  if (!config || !window.supabase) {
    console.warn('Supabase non chargé : accès catégories ignoré.');
    return;
  }

  const client = window.supabase.createClient(config.url, config.anonKey);
  const rank = {
    membre: 0,
    helper: 1,
    helpeur: 1,
    moderateur: 2,
    staff: 3,
    admin: 4,
    'co-fonda': 5,
    direction: 5,
    fondateur: 6
  };

  async function getRole() {
    const { data: { user }, error: authError } = await client.auth.getUser();
    if (authError || !user) return 'membre';

    const { data, error } = await client
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();

    if (error) {
      console.error('Impossible de récupérer le rôle :', error);
      return 'membre';
    }
    return data?.role || 'membre';
  }

  function canSee(category, role) {
    const visibility = (category.visibility || 'public').toLowerCase();
    if (visibility === 'public') return true;
    if (visibility === 'membre') return true;
    return (rank[role] ?? 0) >= (rank[visibility] ?? 99);
  }

  async function loadCategories() {
    const role = await getRole();
    const { data, error } = await client
      .from('categories')
      .select('id,title,description,icon,visibility,position')
      .order('position', { ascending: true });

    if (error) {
      console.error('Impossible de récupérer les catégories :', error);
      return;
    }

    window.HUB_USER_ROLE = role;
    window.HUB_CATEGORIES = (data || []).filter(category => canSee(category, role));
    document.dispatchEvent(new CustomEvent('hub:categories-loaded', {
      detail: { role, categories: window.HUB_CATEGORIES }
    }));
  }

  window.HUB_GET_ROLE = getRole;
  window.HUB_LOAD_CATEGORIES = loadCategories;
  loadCategories();
})();
