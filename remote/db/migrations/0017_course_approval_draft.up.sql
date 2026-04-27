UPDATE course_catalog_entries ce
LEFT JOIN course_upload_requests cur
  ON cur.course_id = ce.course_id
 AND cur.status = 'pending'
LEFT JOIN bundles b
  ON b.course_id = ce.course_id
LEFT JOIN bundle_versions bv
  ON bv.bundle_id = b.id
SET ce.approval_status = 'draft'
WHERE ce.approval_status = 'pending'
  AND cur.id IS NULL
  AND bv.id IS NULL;
