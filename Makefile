QMLLINT := /usr/lib/qt6/bin/qmllint
QML_FILES := Panel.qml Service.qml $(wildcard components/*.qml)

.PHONY: test validate qml-check

test:
	node tests/test_model.js
	bash tests/test_panel_source.sh
	python3 -I -B -c 'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' backend/xray-omarchy backend/xray-omarchy-helper
	bash -n backend/install.sh backend/uninstall.sh backend/killswitch-test backend/update-sums.sh backend/pin-core.sh
	backend/update-sums.sh --check
	python3 -I -B tests/check_versions.py

# qmllint with the system shell's modules (qs.Commons, qs.Ui) importable.
qml-check:
	$(QMLLINT) -I /usr/share/omarchy/shell $(QML_FILES)

validate: test
	omarchy plugin validate .
