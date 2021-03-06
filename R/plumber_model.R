#' Añade la funcionalidad a un objeto plumber de poder simular requests desde
#' R sin tener que levantar la API. Ayuda para testeo.
PlumberMocker <- R6Class(
  inherit = plumber::plumber,
  classname = "Plumbermocker",
  public = list(
    #' Simula una petición a la api.
    #' @param verb Verbo de peticion "GET", "POST" ...
    #' @param path Url de la petición, por ejemplo '/foo'.
    #' @param query_str Parametros como una url query 'foo=1&&bar=fooBar'.
    #' @param body Cuerpo de la petición, por ejemplo un JSON.
    request = function(verb, path, query_str = "", body = ""){
      self$serve(
        private$makeRequest(verb, path, query_str, body),
        private$PlumberResponse$new()
      )
    },
    #' Especializacion del metodo request para peticiones GET.
    get = function(...) self$request(verb = "GET", ...),
    #' Especializacion del metodo request para peticiones POST.
    post = function(...) self$request(verb = "POST", ...)
  ),
  private = list(
    PlumberResponse = getFromNamespace("PlumberResponse", "plumber"),
    makeRequest = function(verb, path, query_str = "", body = ""){
      req <- new.env()
      req$REQUEST_METHOD <- toupper(verb)
      req$PATH_INFO <- path
      req$QUERY_STRING <- query_str
      req$rook.input <- list(read_lines = function(){ body })
      req
    }
  )
)

PlumberModel <- R6Class(
  classname = "PlumberModel",
  inherit = PlumberMocker,
  #' Métodos públicos. Las clases hijas los deben implementar si el modelo es
  #' distinto para ser compatibles con la api.
  public = list(
    #' Constructor de la api.
    #' @param model Modelo base de la API.
    initialize = function(model){
      super$initialize()
      self$setModel(model)
      self$setErrorHandler(private$handleHttpErrors)
      private$buildEndPoints()
    },
    #' Obtiene una copia del modelo base.
    #' @return Copia del modelo base.
    getModel = function(){
      private$model
    },
    #' Fija el modelo base.
    #' @return Referencia a sí mismo.
    setModel = function(model){
      private$model <- model
      self
    },
    #' Obtiene información sobre el modelo.
    #' @return Lista con información básica sobre el modelo.
    modelInfo = function(){
      modelInfo(private$model)
    },
    #' Resultados del entrenamiento.
    #' @return data.frame con los resultados del entrenamiento en función de
    #' los hiperparámetros del modelo.
    trainResults = function(){
      trainResults(private$model)
    },
    #' Definición de las variables del modelo.
    #' @return Lista con las variables e información sobre las mismas.
    inputFeatures = function(){
      inputFeatures(private$model)
    },
    #' Predice el modelo.
    #' @param X data.frame con las variables independientes.
    #' @return Vector con las predicciones de la variable objetivo.
    predict = function(X){
      predict(private$model, X)
    }
  ),
  # Métodos privados. Pueden ser sobreescritos por clases hijas.
  private = list(
    model = NULL,
    #' Define los endpoints de la API.
    buildEndPoints = function(){
      self$handle("GET", "/modelInfo", function(req, res){
        self$modelInfo()
      })
      self$handle("GET", "/trainResults", function(req, res){
        self$trainResults()
      })
      self$handle("GET", "/inputFeatures", function(req, res){
        self$inputFeatures()
      })
      self$handle("GET", "/predict", function(req, res){
        private$getRequestArgs(req) %>%
          coerceData(self$inputFeatures()) %>%
          self$predict()
      })
      self$handle("POST", "/predict", function(req, res){
        X <- jsonlite::fromJSON(req$postBody)
        if(!("data.frame" %in% class(X)))
          stop("parse error: Couldn't parse request as a valid data.frame.")
        coerceData(X, self$inputFeatures()) %>%
          self$predict()
      })
    },
    #' Obtiene los argumentos de la query url como un data.frame. Todas las
    #' columnas son de caracteres.
    #' @param req Objeto request.
    #' @return data.frame con los argumentos.
    getRequestArgs = function(req){
      req$args %>%
        map(~ if(is.character(.x)) .x) %>%
        compact() %>%
        as_tibble()
    },
    #' Maneja los errores que se producen en los endpoints.
    #' @param req Objeto de peticion.
    #' @param res Objeto de respuesta.
    #' @param err Objeto de error.
    handleHttpErrors = function(req, res, err){
      # Chequeamos si es un error conocido.
      known.errors <- c("parse", "validation")
      known.err.rgx <- paste0("^", known.errors, " error:")
      errorKnown <- FALSE
      # Si el error lo hemos generado nosotros durante la validación mandamos
      # un 400: Bad request, sino mandamos un 500: Internal server error.
      res$status <- if(errorKnown) 400 else 500
      # Además enviamos el mensaje de error en el cuerpo de la respuesta.
      print(err)
      list(error = jsonlite::unbox(err$message))
    }
  )
)

#' Añade a la API un servidor web de archivos estáticos que se monta sobre la
#' url '/'.
PlumberModelWebApp <- R6Class(
  inherit = PlumberModel,
  public = list(
    #' Constructor
    #' @param model Modelo sobre el que se construye la API.
    #' @param static.dir Directorio desde el que se sirven los archivos.
    #' estaticos.
    initialize = function(model, static.dir = NULL){
      super$initialize(model)
      private$buildStaticFileServer(static.dir)
    }
  ),
  private = list(
    #' Construye el servidor de archivos estáticos.
    #' @param static.dir Directorio desde el que se sirven los archivos.
    buildStaticFileServer = function(static.dir = NULL){
      default.folder <-
        if(is.null(packageName())){
          "inst/www/"
        } else {
          system.file("www", package = packageName())
        }
      folder <- if(is.null(static.dir)) default.folder else static.dir
      static <- plumber::PlumberStatic$new(folder)
      self$mount("/", static)
    }
  )
)

if(F){
    api <- PlumberModel$new(mdl)
    api$run(port = 9999)
}
