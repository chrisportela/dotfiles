{
  lib,
  python3Packages,
  fetchPypi,
}:

let
  plane-sdk = python3Packages.buildPythonPackage rec {
    pname = "plane_sdk";
    version = "0.2.21";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-0s1A6gHd96/fYcFjm46MtvUyIzSKmuKr9SGp1RDav5E=";
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
  version = "0.2.10";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-5H/yVfA/FZ5O5S1NQbYcZjYLeOE/wHYB+LaWIIjck7Y=";
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
