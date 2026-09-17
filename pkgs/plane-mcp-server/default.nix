{
  lib,
  python3Packages,
  fetchPypi,
}:

let
  plane-sdk = python3Packages.buildPythonPackage rec {
    pname = "plane_sdk";
    version = "0.3.0";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-CrbGxxi4+yJ0C5xlKpmuLrvyX+ssnbcKdiCY69rK5NI=";
    };

    build-system = [ python3Packages.setuptools ];

    dependencies = with python3Packages; [
      requests
      pydantic
    ];

    pythonImportsCheck = [ "plane" ];
  };
in
python3Packages.buildPythonApplication rec {
  pname = "plane_mcp_server";
  version = "0.3.2";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-5Thb3QWVoA0wOlEcV9zozNI6CLxzFQwGqrcqEvYAIuM=";
  };

  build-system = [ python3Packages.setuptools ];

  dependencies =
    (with python3Packages; [
      fastmcp
      plane-sdk
      py-key-value-aio
      mcp
      boto3
      fakeredis
    ])
    # Upstream declares `py-key-value-aio[redis]`; server.py imports RedisStore
    # unconditionally at module load, so the redis backend must be present.
    ++ python3Packages.py-key-value-aio.optional-dependencies.redis;

  pythonRelaxDeps = true;

  passthru.updateScript = ./update.sh;

  # Import server.py too: it pulls in the redis backend at module load, so this
  # turns the missing-redis runtime crash into a build-time failure.
  pythonImportsCheck = [
    "plane_mcp"
    "plane_mcp.server"
  ];

  meta = {
    description = "Model Context Protocol server for Plane project management integration";
    homepage = "https://pypi.org/project/plane-mcp-server/";
    license = lib.licenses.mit;
    mainProgram = "plane-mcp-server";
    platforms = lib.platforms.unix;
  };
}
