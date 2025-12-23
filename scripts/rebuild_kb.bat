@echo off
setlocal

set CONFIG=config.yaml
python app/ingest.py --config %CONFIG%

endlocal
