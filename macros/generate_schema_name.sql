{#-
    Override dbt's default schema naming so custom schemas are used as-is
    (staging, intermediate, marts) instead of being prefixed with the
    target schema (main_staging, main_intermediate, ...).
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
