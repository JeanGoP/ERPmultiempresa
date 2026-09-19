# Retenciones al leer XML

Se excluyen las **autorretenciones identificadas por nombre**, tanto en encabezado como en líneas, incluyendo componentes de TaxTotal y campos personalizados. Se toleran tildes, mayúsculas, guiones y espacios, y las variantes autorretención/autoretención/autorretefuente. No se identifica una autorretención únicamente por el código 06 ni por su porcentaje, porque también los usan retenciones ordinarias.

Esta regla reemplaza el antiguo mínimo del 2%: las retenciones ordinarias se conservan incluso al 1,25%, por debajo del 1% o sin tarifa informada. Los totales personalizados no vuelven a incorporar autorretenciones excluidas de componentes estándar. Si solo se informa un total genérico junto a una autorretención personalizada, no se infiere que ese agregado sea una retención ordinaria.

La lectura usa los datos del XML; no inventa importes que aparezcan únicamente en un PDF. Los valores sin identificación suficiente requieren revisión manual.

La tarjeta **Retenciones** del resumen superior siempre está visible y es editable, incluso en cero. Las líneas permanecen de solo lectura. Un ajuste manual no vuelve a pasar por la clasificación automática del XML: es una decisión explícita del usuario.

Al editar el total se distribuye internamente entre las líneas, proporcionalmente a su valor más impuestos, conciliando centavos, para utilizar los campos existentes de guardado. Se actualizan el resumen, el detalle de retenciones y el total a pagar por la diferencia. La lectura inicial respeta el total a pagar informado en el XML, sin descontar ni sumar automáticamente las retenciones excluidas. El XML original no se modifica. Se rechazan valores negativos, no finitos o superiores a los límites del documento. La edición se bloquea después de guardar.

Validaciones: `npm test` y `node tests/xml-retention-smoke.js`.
