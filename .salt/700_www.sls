{% import "makina-states/services/http/nginx/init.sls" as nginx %}
{% set cfg = opts['ms_project'] %}
{% set data = cfg.data %}
{% set scfg = salt['mc_utils.json_dump'](cfg) %}
include:
  - makina-states.services.http.nginx

{{ nginx.virtualhost(domain=data.ui_domain,
                     active=True,
                     doc_root=data.docroot,
                     cfg=cfg,
                     force_restart=True,
                     vh_top_source=data.nginx_ui_upstreams,
                     vh_content_source=data.ui_vhost) }}

{{ nginx.virtualhost(domain=data.domain,
                     active=True,
                     doc_root=data.docroot,
                     cfg=cfg,
                     force_restart=True,
                     server_aliases=data.server_aliases,
                     redirect_aliases=False,
                     vh_top_source=data.nginx_upstreams,
                     vh_content_source=data.vhost) }}

# generate one htpasswd file per location to restrict
{% for locdefs in data.get('http_downloads', []) %}
{% for loc, locdata in locdefs.items() %}
{% set htpasswd = '/etc/htpasswd.{0}'.format(loc.replace('/', 'slash_')) %}
{{cfg.name}}-{{loc}}-htpasswd:
  file.managed:
    - name: {{htpasswd}}
    - source: ''
    - user: www-data
    - group: www-data
    - mode: 770
    - watch_in:
      - mc_proxy: nginx-pre-conf-hook

{% if locdata.get('users', []) %}
{% for userrow in data.users %}
{% for user, udata in userrow.items() %}
{% if user in locdata.users %}
{{cfg.name}}-{{user}}-htpasswd-{{htpasswd}}:
  webutil.user_exists:
    - name: {{user}}
    - password: {{udata.password}}
    - htpasswd_file: {{htpasswd}}
    - options: m
    - force: true
    - watch:
      - file: {{cfg.name}}-{{loc}}-htpasswd
    - watch_in:
      - mc_proxy: nginx-pre-conf-hook
{% endif %}
{% endfor %}
{% endfor %}
{% endif %}
{% endfor %}
{% endfor %}
