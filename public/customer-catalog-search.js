/* Búsqueda local del catálogo cargado para la factura de venta. */
(() => {
  const fold = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es-CO').trim();
  const key = (articleId, warehouseId) => `${articleId}|${warehouseId}`;

  function indexArticles(articles = [], serials = []) {
    const identifiers = new Map();
    for (const serial of serials) {
      if (!serial.valor) continue;
      const itemKey = key(serial.articuloId, serial.bodegaId);
      if (!identifiers.has(itemKey)) identifiers.set(itemKey, []);
      identifiers.get(itemKey).push({ id: serial.id, type: serial.tipo || 'Serial', value: serial.valor, search: fold(`${serial.tipo || 'Serial'} ${serial.valor}`), exact: fold(serial.valor) });
    }
    return articles.map(article => ({
      article,
      search: fold(`${article.codigo} ${article.descripcion} ${article.bodegaCodigo} ${article.bodega}`),
      identifiers: identifiers.get(key(article.id, article.bodegaId)) || [],
    }));
  }

  function findArticles(index, branchId, query, limit = 20) {
    const text = fold(query);
    const terms = text.split(/\s+/).filter(Boolean);
    if (!terms.length) return { items: [], total: 0 };
    const found = [];
    for (const entry of index) {
      if (String(entry.article.sucursalId) !== String(branchId)) continue;
      const matches = entry.identifiers.filter(identifier => terms.some(term => identifier.search.includes(term)));
      if (!terms.every(term => entry.search.includes(term) || matches.some(identifier => identifier.search.includes(term)))) continue;
      const exactSerial = entry.identifiers.find(identifier => identifier.exact === text || identifier.search === text);
      const code = fold(entry.article.codigo);
      const rank = exactSerial ? 0 : code === text ? 1 : code.startsWith(text) ? 2 : fold(entry.article.descripcion).startsWith(text) ? 3 : matches.length ? 4 : 5;
      found.push({ ...entry, matches, exactSerialId: exactSerial?.id || null, rank });
    }
    found.sort((a, b) => a.rank - b.rank || String(a.article.descripcion).localeCompare(String(b.article.descripcion), 'es-CO') || String(a.article.bodegaCodigo).localeCompare(String(b.article.bodegaCodigo), 'es-CO'));
    return { items: found.slice(0, limit), total: found.length };
  }

  function findConcepts(concepts = [], query, limit = 20) {
    const terms = fold(query).split(/\s+/).filter(Boolean);
    if (!terms.length) return { items: [], total: 0 };
    const found = concepts.filter(concept => {
      const text = fold(`${concept.codigo} ${concept.nombre} ${concept.cuentaIngresoZeus}`);
      return terms.every(term => text.includes(term));
    });
    return { items: found.slice(0, limit), total: found.length };
  }

  const api = { fold, indexArticles, findArticles, findConcepts };
  if (typeof window !== 'undefined') window.customerCatalogSearch = api;
  if (typeof module !== 'undefined') module.exports = api;
})();
