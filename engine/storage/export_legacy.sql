-- Export functions for restoration into a prior-release schema. No table DDL.
CREATE OR REPLACE FUNCTION pg_temp.export_calculation_titles(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='{}'::jsonb;
 FOR n IN SELECT * FROM calculation_titles WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_object(n.map_key,item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_descriptions(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='{}'::jsonb;
 FOR n IN SELECT * FROM calculation_descriptions WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_object(n.map_key,item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_unions(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_unions WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_lookup_keys(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_lookup_keys WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_lookup_matches(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_lookup_matches WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_lookup_fields(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_lookup_fields WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_lookups(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_lookups WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('collection',to_jsonb(n."collection"));
item=item||jsonb_build_object('prefix',to_jsonb(n."prefix"));
item=item||jsonb_build_object('key',pg_temp.export_calculation_lookup_keys(p,c,v,n.row_key));
item=item||jsonb_build_object('match',pg_temp.export_calculation_lookup_matches(p,c,v,n.row_key));
item=item||jsonb_build_object('fields',pg_temp.export_calculation_lookup_fields(p,c,v,n.row_key));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_buckets(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_buckets WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('field',to_jsonb(n."field"));
item=item||jsonb_build_object('unit',to_jsonb(n."unit"));
item=item||jsonb_build_object('name',to_jsonb(n."name"));
item=item||jsonb_build_object('utc_offset_minutes',to_jsonb(n."utc_offset_minutes"));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_row_derived(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_row_derived WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('name',to_jsonb(n."name"));
item=item||jsonb_build_object('expr',to_jsonb(n."expr"));
item=item||jsonb_build_object('expr_field',to_jsonb(n."expr_field"));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_conditions_values(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; child record; result jsonb;
BEGIN
 SELECT * INTO n FROM calculation_conditions_values WHERE project_slug=p AND calculation_id=c AND version=v AND row_key=par;
 IF NOT FOUND THEN
  SELECT * INTO n FROM calculation_conditions_values WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par AND node_parent_key IS NULL;
 END IF;
 IF NOT FOUND THEN RETURN 'null'::jsonb;END IF;
 IF n.node_kind IN ('object','array') THEN
  result=CASE n.node_kind WHEN 'object' THEN '{}'::jsonb ELSE '[]'::jsonb END;
  FOR child IN SELECT * FROM calculation_conditions_values WHERE project_slug=p AND calculation_id=c AND version=v AND node_parent_key=n.row_key ORDER BY position LOOP
   IF n.node_kind='object' THEN result=result||jsonb_build_object(child.map_key,pg_temp.export_calculation_conditions_values(p,c,v,child.row_key));ELSE result=result||jsonb_build_array(pg_temp.export_calculation_conditions_values(p,c,v,child.row_key));END IF;
  END LOOP;
  RETURN result;
 ELSIF n.node_kind='string' THEN RETURN to_jsonb(n.scalar_value);
 ELSIF n.node_kind='null' THEN RETURN 'null'::jsonb;
 ELSE RETURN n.scalar_value::jsonb; END IF;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_conditions(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_conditions WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('field',to_jsonb(n."field"));
item=item||jsonb_build_object('op',to_jsonb(n."op"));
item=item||jsonb_build_object('value',pg_temp.export_calculation_conditions_values(p,c,v,n.row_key));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_filter_labels(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='{}'::jsonb;
 FOR n IN SELECT * FROM calculation_filter_labels WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_object(n.map_key,item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_filters(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_filters WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('field',to_jsonb(n."field"));
item=item||jsonb_build_object('type',to_jsonb(n."type"));
item=item||jsonb_build_object('scope',to_jsonb(n."scope"));
item=item||jsonb_build_object('label',pg_temp.export_calculation_filter_labels(p,c,v,n.row_key));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_stage_groups(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_stage_groups WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_stage_partitions(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_stage_partitions WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_measure_fields(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_measure_fields WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_measure_conditions_values(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; child record; result jsonb;
BEGIN
 SELECT * INTO n FROM calculation_measure_conditions_values WHERE project_slug=p AND calculation_id=c AND version=v AND row_key=par;
 IF NOT FOUND THEN
  SELECT * INTO n FROM calculation_measure_conditions_values WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par AND node_parent_key IS NULL;
 END IF;
 IF NOT FOUND THEN RETURN 'null'::jsonb;END IF;
 IF n.node_kind IN ('object','array') THEN
  result=CASE n.node_kind WHEN 'object' THEN '{}'::jsonb ELSE '[]'::jsonb END;
  FOR child IN SELECT * FROM calculation_measure_conditions_values WHERE project_slug=p AND calculation_id=c AND version=v AND node_parent_key=n.row_key ORDER BY position LOOP
   IF n.node_kind='object' THEN result=result||jsonb_build_object(child.map_key,pg_temp.export_calculation_measure_conditions_values(p,c,v,child.row_key));ELSE result=result||jsonb_build_array(pg_temp.export_calculation_measure_conditions_values(p,c,v,child.row_key));END IF;
  END LOOP;
  RETURN result;
 ELSIF n.node_kind='string' THEN RETURN to_jsonb(n.scalar_value);
 ELSIF n.node_kind='null' THEN RETURN 'null'::jsonb;
 ELSE RETURN n.scalar_value::jsonb; END IF;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_measure_conditions(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_measure_conditions WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('field',to_jsonb(n."field"));
item=item||jsonb_build_object('op',to_jsonb(n."op"));
item=item||jsonb_build_object('value',pg_temp.export_calculation_measure_conditions_values(p,c,v,n.row_key));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_measures(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_measures WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('name',to_jsonb(n."name"));
item=item||jsonb_build_object('agg',to_jsonb(n."agg"));
item=item||jsonb_build_object('field',to_jsonb(n."field"));
item=item||jsonb_build_object('by',to_jsonb(n."by"));
item=item||jsonb_build_object('n',to_jsonb(n."n"));
item=item||jsonb_build_object('fields',pg_temp.export_calculation_measure_fields(p,c,v,n.row_key));
item=item||jsonb_build_object('where',pg_temp.export_calculation_measure_conditions(p,c,v,n.row_key));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_stage_derived(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_stage_derived WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('name',to_jsonb(n."name"));
item=item||jsonb_build_object('expr',to_jsonb(n."expr"));
item=item||jsonb_build_object('expr_field',to_jsonb(n."expr_field"));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_stage_having_values(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; child record; result jsonb;
BEGIN
 SELECT * INTO n FROM calculation_stage_having_values WHERE project_slug=p AND calculation_id=c AND version=v AND row_key=par;
 IF NOT FOUND THEN
  SELECT * INTO n FROM calculation_stage_having_values WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par AND node_parent_key IS NULL;
 END IF;
 IF NOT FOUND THEN RETURN 'null'::jsonb;END IF;
 IF n.node_kind IN ('object','array') THEN
  result=CASE n.node_kind WHEN 'object' THEN '{}'::jsonb ELSE '[]'::jsonb END;
  FOR child IN SELECT * FROM calculation_stage_having_values WHERE project_slug=p AND calculation_id=c AND version=v AND node_parent_key=n.row_key ORDER BY position LOOP
   IF n.node_kind='object' THEN result=result||jsonb_build_object(child.map_key,pg_temp.export_calculation_stage_having_values(p,c,v,child.row_key));ELSE result=result||jsonb_build_array(pg_temp.export_calculation_stage_having_values(p,c,v,child.row_key));END IF;
  END LOOP;
  RETURN result;
 ELSIF n.node_kind='string' THEN RETURN to_jsonb(n.scalar_value);
 ELSIF n.node_kind='null' THEN RETURN 'null'::jsonb;
 ELSE RETURN n.scalar_value::jsonb; END IF;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_stage_having(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_stage_having WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('field',to_jsonb(n."field"));
item=item||jsonb_build_object('op',to_jsonb(n."op"));
item=item||jsonb_build_object('value',pg_temp.export_calculation_stage_having_values(p,c,v,n.row_key));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_window_partitions(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_window_partitions WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_windows(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_windows WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('name',to_jsonb(n."name"));
item=item||jsonb_build_object('agg',to_jsonb(n."agg"));
item=item||jsonb_build_object('field',to_jsonb(n."field"));
item=item||jsonb_build_object('size',to_jsonb(n."size"));
item=item||jsonb_build_object('order_by',to_jsonb(n."order_by"));
item=item||jsonb_build_object('partition_by',pg_temp.export_calculation_window_partitions(p,c,v,n.row_key));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_stages(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_stages WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('group_by',pg_temp.export_calculation_stage_groups(p,c,v,n.row_key));
item=item||jsonb_build_object('partition_by',pg_temp.export_calculation_stage_partitions(p,c,v,n.row_key));
item=item||jsonb_build_object('measures',pg_temp.export_calculation_measures(p,c,v,n.row_key));
item=item||jsonb_build_object('derived',pg_temp.export_calculation_stage_derived(p,c,v,n.row_key));
item=item||jsonb_build_object('having',pg_temp.export_calculation_stage_having(p,c,v,n.row_key));
item=item||jsonb_build_object('windows',pg_temp.export_calculation_windows(p,c,v,n.row_key));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_derived(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_derived WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('name',to_jsonb(n."name"));
item=item||jsonb_build_object('expr',to_jsonb(n."expr"));
item=item||jsonb_build_object('expr_field',to_jsonb(n."expr_field"));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_having_values(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; child record; result jsonb;
BEGIN
 SELECT * INTO n FROM calculation_having_values WHERE project_slug=p AND calculation_id=c AND version=v AND row_key=par;
 IF NOT FOUND THEN
  SELECT * INTO n FROM calculation_having_values WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par AND node_parent_key IS NULL;
 END IF;
 IF NOT FOUND THEN RETURN 'null'::jsonb;END IF;
 IF n.node_kind IN ('object','array') THEN
  result=CASE n.node_kind WHEN 'object' THEN '{}'::jsonb ELSE '[]'::jsonb END;
  FOR child IN SELECT * FROM calculation_having_values WHERE project_slug=p AND calculation_id=c AND version=v AND node_parent_key=n.row_key ORDER BY position LOOP
   IF n.node_kind='object' THEN result=result||jsonb_build_object(child.map_key,pg_temp.export_calculation_having_values(p,c,v,child.row_key));ELSE result=result||jsonb_build_array(pg_temp.export_calculation_having_values(p,c,v,child.row_key));END IF;
  END LOOP;
  RETURN result;
 ELSIF n.node_kind='string' THEN RETURN to_jsonb(n.scalar_value);
 ELSIF n.node_kind='null' THEN RETURN 'null'::jsonb;
 ELSE RETURN n.scalar_value::jsonb; END IF;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_having(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_having WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('field',to_jsonb(n."field"));
item=item||jsonb_build_object('op',to_jsonb(n."op"));
item=item||jsonb_build_object('value',pg_temp.export_calculation_having_values(p,c,v,n.row_key));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_calculator_values(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; child record; result jsonb;
BEGIN
 SELECT * INTO n FROM calculation_calculator_values WHERE project_slug=p AND calculation_id=c AND version=v AND row_key=par;
 IF NOT FOUND THEN
  SELECT * INTO n FROM calculation_calculator_values WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par AND node_parent_key IS NULL;
 END IF;
 IF NOT FOUND THEN RETURN 'null'::jsonb;END IF;
 IF n.node_kind IN ('object','array') THEN
  result=CASE n.node_kind WHEN 'object' THEN '{}'::jsonb ELSE '[]'::jsonb END;
  FOR child IN SELECT * FROM calculation_calculator_values WHERE project_slug=p AND calculation_id=c AND version=v AND node_parent_key=n.row_key ORDER BY position LOOP
   IF n.node_kind='object' THEN result=result||jsonb_build_object(child.map_key,pg_temp.export_calculation_calculator_values(p,c,v,child.row_key));ELSE result=result||jsonb_build_array(pg_temp.export_calculation_calculator_values(p,c,v,child.row_key));END IF;
  END LOOP;
  RETURN result;
 ELSIF n.node_kind='string' THEN RETURN to_jsonb(n.scalar_value);
 ELSIF n.node_kind='null' THEN RETURN 'null'::jsonb;
 ELSE RETURN n.scalar_value::jsonb; END IF;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_parameters(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='{}'::jsonb;
 FOR n IN SELECT * FROM calculation_parameters WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_object(n.map_key,item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_references(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='{}'::jsonb;
 FOR n IN SELECT * FROM calculation_references WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('dataset',to_jsonb(n."dataset"));
item=item||jsonb_build_object('field',to_jsonb(n."field"));
result=result||jsonb_build_object(n.map_key,item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_sort(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_sort WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('field',to_jsonb(n."field"));
item=item||jsonb_build_object('desc',n."desc"::jsonb);
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_field_labels(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='{}'::jsonb;
 FOR n IN SELECT * FROM calculation_field_labels WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_object(n.map_key,item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_fields(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='[]'::jsonb;
 FOR n IN SELECT * FROM calculation_fields WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('name',to_jsonb(n."name"));
item=item||jsonb_build_object('type',to_jsonb(n."type"));
item=item||jsonb_build_object('role',to_jsonb(n."role"));
item=item||jsonb_build_object('unit',to_jsonb(n."unit"));
item=item||jsonb_build_object('decimals',to_jsonb(n."decimals"));
item=item||jsonb_build_object('label',pg_temp.export_calculation_field_labels(p,c,v,n.row_key));
result=result||jsonb_build_array(item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_value_texts(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='{}'::jsonb;
 FOR n IN SELECT * FROM calculation_value_texts WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item=to_jsonb(n.value);
result=result||jsonb_build_object(n.map_key,item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_value_labels(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='{}'::jsonb;
 FOR n IN SELECT * FROM calculation_value_labels WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=pg_temp.export_calculation_value_texts(p,c,v,n.row_key);
result=result||jsonb_build_object(n.map_key,item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_value_fields(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='{}'::jsonb;
 FOR n IN SELECT * FROM calculation_value_fields WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=pg_temp.export_calculation_value_labels(p,c,v,n.row_key);
result=result||jsonb_build_object(n.map_key,item);
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_calculation_definitions(p text,c text,v bigint,par text) RETURNS jsonb LANGUAGE plpgsql AS $export$
DECLARE n record; result jsonb; item jsonb;
BEGIN
 result='null'::jsonb;
 FOR n IN SELECT * FROM calculation_definitions WHERE project_slug=p AND calculation_id=c AND version=v AND parent_key=par ORDER BY position LOOP
item='{}'::jsonb;
item=item||jsonb_build_object('equation',to_jsonb(n."equation"));
item=item||jsonb_build_object('source',to_jsonb(n."source"));
item=item||jsonb_build_object('limit',to_jsonb(n."limit"));
item=item||jsonb_build_object('warm',n."warm"::jsonb);
item=item||jsonb_build_object('title',pg_temp.export_calculation_titles(p,c,v,n.row_key));
item=item||jsonb_build_object('description',pg_temp.export_calculation_descriptions(p,c,v,n.row_key));
item=item||jsonb_build_object('union',pg_temp.export_calculation_unions(p,c,v,n.row_key));
item=item||jsonb_build_object('lookups',pg_temp.export_calculation_lookups(p,c,v,n.row_key));
item=item||jsonb_build_object('buckets',pg_temp.export_calculation_buckets(p,c,v,n.row_key));
item=item||jsonb_build_object('row_derived',pg_temp.export_calculation_row_derived(p,c,v,n.row_key));
item=item||jsonb_build_object('where',pg_temp.export_calculation_conditions(p,c,v,n.row_key));
item=item||jsonb_build_object('filters',pg_temp.export_calculation_filters(p,c,v,n.row_key));
item=item||jsonb_build_object('stages',pg_temp.export_calculation_stages(p,c,v,n.row_key));
item=item||jsonb_build_object('derived',pg_temp.export_calculation_derived(p,c,v,n.row_key));
item=item||jsonb_build_object('having',pg_temp.export_calculation_having(p,c,v,n.row_key));
item=item||jsonb_build_object('calculator',pg_temp.export_calculation_calculator_values(p,c,v,n.row_key));
item=item||jsonb_build_object('params',pg_temp.export_calculation_parameters(p,c,v,n.row_key));
item=item||jsonb_build_object('refs',pg_temp.export_calculation_references(p,c,v,n.row_key));
item=item||jsonb_build_object('sort',pg_temp.export_calculation_sort(p,c,v,n.row_key));
item=item||jsonb_build_object('fields',pg_temp.export_calculation_fields(p,c,v,n.row_key));
item=item||jsonb_build_object('value_labels',pg_temp.export_calculation_value_fields(p,c,v,n.row_key));
result=item;
 END LOOP;
 RETURN result;
END
$export$;

CREATE OR REPLACE FUNCTION pg_temp.export_card_properties(p0 text,p1 text,p2 text,node bigint DEFAULT 0) RETURNS jsonb LANGUAGE plpgsql AS $property$
DECLARE n record;child record;result jsonb;
BEGIN
 SELECT * INTO n FROM card_properties WHERE project_slug=p0 AND report_slug=p1 AND card_id=p2 AND node_id=node;
 IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
 IF n.value_kind IN ('object','array') THEN
  result=CASE n.value_kind WHEN 'object' THEN '{}'::jsonb ELSE '[]'::jsonb END;
  FOR child IN SELECT * FROM card_properties WHERE project_slug=p0 AND report_slug=p1 AND card_id=p2 AND parent_id=node ORDER BY position LOOP
   IF n.value_kind='object' THEN result=result||jsonb_build_object(child.property_name,pg_temp.export_card_properties(p0,p1,p2,child.node_id));ELSE result=result||jsonb_build_array(pg_temp.export_card_properties(p0,p1,p2,child.node_id));END IF;
  END LOOP; RETURN result;
 ELSIF n.value_kind='string' THEN RETURN to_jsonb(n.scalar_value);
 ELSIF n.value_kind='null' THEN RETURN 'null'::jsonb; ELSE RETURN n.scalar_value::jsonb;END IF;
END $property$;

CREATE OR REPLACE FUNCTION pg_temp.export_setting_properties(p0 text,node bigint DEFAULT 0) RETURNS jsonb LANGUAGE plpgsql AS $property$
DECLARE n record;child record;result jsonb;
BEGIN
 SELECT * INTO n FROM setting_properties WHERE key=p0 AND node_id=node;
 IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
 IF n.value_kind IN ('object','array') THEN
  result=CASE n.value_kind WHEN 'object' THEN '{}'::jsonb ELSE '[]'::jsonb END;
  FOR child IN SELECT * FROM setting_properties WHERE key=p0 AND parent_id=node ORDER BY position LOOP
   IF n.value_kind='object' THEN result=result||jsonb_build_object(child.property_name,pg_temp.export_setting_properties(p0,child.node_id));ELSE result=result||jsonb_build_array(pg_temp.export_setting_properties(p0,child.node_id));END IF;
  END LOOP; RETURN result;
 ELSIF n.value_kind='string' THEN RETURN to_jsonb(n.scalar_value);
 ELSIF n.value_kind='null' THEN RETURN 'null'::jsonb; ELSE RETURN n.scalar_value::jsonb;END IF;
END $property$;
