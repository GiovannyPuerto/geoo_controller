# Remove Redundant Code from Inventory Views

## Tasks
- [ ] Replace `safe_decimal` function with `clean_number` from utils.py
- [ ] Remove `upload_base_file` function (redundant - just calls update_inventory)
- [ ] Remove `welcome` function (unnecessary for inventory API)
- [ ] Consolidate duplicated stock calculation logic between `get_product_analysis` and `get_summary`
- [ ] Create shared PDF generation helper function for export functions
- [ ] Update URL patterns in urls.py to remove redundant endpoints
- [ ] Update imports in views.py
