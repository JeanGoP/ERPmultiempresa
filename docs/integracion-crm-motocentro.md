# Integración piloto CRM → ERP: Motocentro

La primera entrega recibe una solicitud de crédito aprobada del CRM como ficha pendiente de revisión. No crea factura, asiento, cartera ni movimiento de inventario.

## Identidad y correspondencias

- Cada empresa CRM (`Guid`) se vincula expresamente con una empresa ERP (`bigint`). El administrador de plataforma escoge la empresa ERP en **Configuración → Conexión con el ERP** del CRM; no se infiere solo del nombre durante un envío.
- NIT confirmado por el propietario: `91452546-1`. El ERP guarda `Nit=91452546` y `DigitoVerificacion=1` por separado; el receptor compara el ID ERP seleccionado y ambos componentes del NIT. El CRM solo encola aprobaciones de una empresa expresamente vinculada. El nombre visible no es una clave definitiva.
- La solicitud CRM y el evento de envío conservan identificadores estables. El ERP rechaza un segundo evento con el mismo identificador si el contenido cambió; un reintento idéntico devuelve la misma recepción.
- Cliente: tipo y número de identificación; artículo: referencia; punto de venta: nombre de sede. La ficha recibida no se convierte en factura automáticamente, aunque haya homologación.

## Contrato de recepción

El sobre incluye ID del evento, ID de empresa CRM, ID de solicitud, número, fecha de aprobación, cliente, artículos, valor aprobado, cuota inicial, plazo, primer vencimiento, asesor y punto de venta. No incluye documentos, consultas de centrales de riesgo ni datos de codeudores en esta primera fase.

El ERP responde con ID de recepción y estado. El CRM guarda el resultado y permite reintentar fallas de transporte sin duplicar fichas.

No se habilita el envío productivo mientras falten la correspondencia de empresa, la ruta interna y la credencial de servicio.

## Seguridad y transición

Ambas API están en el mismo servidor IIS y sus rutas de salud respondieron por loopback con el host `stecno.dyndns.org`. La comunicación CRM → ERP usa `http://127.0.0.1/ERP/` con encabezado `Host: stecno.dyndns.org`, exclusivamente dentro del servidor y con clave compartida de servicio. El receptor rechaza solicitudes que no lleguen desde loopback. No se debe usar el HTTP público para enviar información personal.

## Activación controlada

1. Aplicar la migración ERP `075_crm_approved_credits.sql` y desplegar el backend ERP actualizado.
2. Configurar en el ERP, fuera de Git: `CrmIntegration__Enabled=true` y `CrmIntegration__SharedKey=<clave aleatoria de al menos 32 caracteres>`.
3. Desplegar el backend y frontend CRM actualizados; el backend aplica sus migraciones EF al arrancar. Configurar en el CRM, fuera de Git: `ErpIntegration__Enabled=true`, `ErpIntegration__BaseUrl=http://127.0.0.1/ERP/`, `ErpIntegration__HostHeader=stecno.dyndns.org` y `ErpIntegration__SharedKey=<misma clave>`.
4. En el CRM, entrar como administrador de plataforma, seleccionar la empresa CRM activa y escoger su empresa ERP en **Conexión con el ERP**. La selección se valida contra el catálogo de empresas ERP activas y se guarda para esa empresa CRM. Se repite solo la elección para cada empresa nueva; no se cambia la clave del servidor. No se puede cambiar el destino si ya hay exportaciones, ni asociar una misma empresa ERP a dos empresas CRM.
5. Aprobar una solicitud controlada. Verificar en CRM `ErpCreditExports` el estado `Enviado` y en ERP `ven.CrmApprovedCredit` el estado `PENDIENTE_REVISION`, o consultar `GET /api/v1/companies/{empresaId}/crm-approved-credits` con un usuario ERP autorizado.

Los dos interruptores `Enabled` están apagados por defecto y se configuran una vez por instalación, no por empresa. El CRM guarda el evento junto con la aprobación y reintenta el envío por empresa vinculada; el ERP reconoce reintentos idénticos y rechaza contenido cambiado para la misma solicitud. Las solicitudes anteriores a la vinculación no se exportan automáticamente.
