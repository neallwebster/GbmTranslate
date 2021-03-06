GbmTranslate <- function (gbm_object,
                          model_name,
                          n_trees,
                          model_location,
                          language = "c",
                          missing_value = NULL){

  #verifying input
  if (!inherits(gbm_object, "gbm")){
    stop("uplift: object not of class gbm!")
  }
  if (length(model_name) == 0){
    stop("Model name is not valid")
  }
  if (!file.exists(model_location)){
    stop("The specified directory does not exist!")
  }
  if (!language %in% c("c","sas","java")){
    stop("The language is not supported!")    
  }
  if (n_trees > gbm_object$n.trees){
    n_trees = gbm_object$n.trees
    print (paste0("Number of trees exceeded number fit so far. Using ",
                  as.character(gbm_object$n.trees),"."))
  }
  if (n_trees == 0) {n_trees = gbm_object$n.trees}

  if (language == "c"){
    GBM_Scoring <- paste0("/*gbm(",paste(paste(names(gbm_object$call)[2:length(names(gbm_object$call))],
                                    as.character(gbm_object$call)[2:length(names(gbm_object$call))],
                                    sep="=",collapse=","),sep = "\n"),")*/\n\n")
    GBM_Scoring <- paste0(GBM_Scoring,"#include <float.h> \n")
    GBM_Scoring <- paste0(GBM_Scoring,"#include <stdio.h> \n")
    GBM_Scoring <- paste0(GBM_Scoring,"#include <string.h> \n")
    GBM_Scoring <- paste0(GBM_Scoring,"double ",model_name,"(");
    
    for (i_var in 1:length(gbm_object$var.names)){
      if (class(gbm_object$var.levels[[i_var]]) == "numeric"){
        GBM_Scoring <- paste0(GBM_Scoring,"double ",gbm_object$var.names[i_var],
                              ifelse(i_var == length(gbm_object$var.names),
                                     "){",",\n"))
      } else {
        GBM_Scoring <- paste0(GBM_Scoring,"const char * ",gbm_object$var.names[i_var],
                              ifelse(i_var == length(gbm_object$var.names),
                                     "){",",\n"))        
      }
      
    }
    if (is.null(missing_value)){
    GBM_Scoring <- paste0(GBM_Scoring,"\nconst double MISSING = -DBL_MAX;\n")
    } else {
    GBM_Scoring <- paste0(GBM_Scoring,"\nconst double MISSING = ",as.character(missing_value),";\n")      
    }
    
    GBM_Scoring <- paste0(GBM_Scoring,"double score = 0;\n")
    GBM_Scoring <- paste0(GBM_Scoring,"int done, node;\n")    
    for (i_tree in 1:n_trees){
    scoring_matrix <- pretty.gbm.tree(gbm_object,i_tree)   
    GBM_Scoring <- paste0(GBM_Scoring,
                          "/* Tree ",as.character(i_tree), " */\n")
    GBM_Scoring <- paste0(GBM_Scoring,
                          "/* Total terminal nodes: ",
                          as.character(sum(scoring_matrix$SplitVar == -1)), " */\n")
    GBM_Scoring <- paste0(GBM_Scoring,"done = 0;\n","node = 0;\n")
    GBM_Scoring <- paste0(GBM_Scoring,"while (done == 0) switch (node) {\n")
    for (i_nodes in 1: (nrow(scoring_matrix))){
    GBM_Scoring <- paste0(GBM_Scoring,"case ", as.character(i_nodes - 1),":\n")     
      if (scoring_matrix[i_nodes,'SplitVar'] == -1){
        GBM_Scoring <- paste0(GBM_Scoring,"score += ", 
                              as.character(scoring_matrix[i_nodes,'Prediction']),";\n")
        GBM_Scoring <- paste0(GBM_Scoring,"done = 1;\nbreak;\n")        
        
      } else if (
        class(gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]]) == 'numeric'&&
        names(gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]])[1] == '0%'){
        GBM_Scoring <- paste0(GBM_Scoring," if (",
                              gbm_object$var.names[scoring_matrix[i_nodes,'SplitVar']+1],
                              "== MISSING) {node = ",
                              as.character(scoring_matrix[i_nodes,'MissingNode']),";\n} else if (",
                              gbm_object$var.names[scoring_matrix[i_nodes,'SplitVar']+1],
                              "<= ", as.character(scoring_matrix[i_nodes,'SplitCodePred']),
                              ") {node = ",as.character(scoring_matrix[i_nodes,'LeftNode']),
                              ";\n} else {node = ",as.character(scoring_matrix[i_nodes,'RightNode']),
                              ";\n} \n break; \n") 
      } else if (gbm_object$var.type[scoring_matrix[i_nodes,'SplitVar']+1] == 0){
        name_var <- gbm_object$var.names[scoring_matrix[i_nodes,'SplitVar']+1]
        left_index <- scoring_matrix[i_nodes,'SplitCodePred']
        category_left <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][1:(left_index+0.5)]
        category_right <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][(left_index+1.5):
                                          length(gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]])]
        
        logic_left <- paste(paste0("!strcmp (",name_var,',"',category_left,'")'),collapse='||')
        logic_right<- paste(paste0("!strcmp (",name_var,',"',category_right,'")'),collapse='||')
        
        GBM_Scoring <- paste0(GBM_Scoring," if (",logic_left,") {node = ",
                              as.character(scoring_matrix[i_nodes,'LeftNode']),";\n} else if (",
                              logic_right,") {node = ", 
                              as.character(scoring_matrix[i_nodes,'RightNode']),
                              ";\n} else {node = ",as.character(scoring_matrix[i_nodes,'MissingNode']),
                              ";\n} \n break; \n")
        
      }  else {
        name_var <- gbm_object$var.names[scoring_matrix[i_nodes,'SplitVar']+1]
        left_index <- gbm_object$c.splits[scoring_matrix[i_nodes,'SplitCodePred'] + 1][[1]]
        category_left <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][left_index==-1]
        category_right <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][left_index==1]
        category_absent <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][left_index==0]
        if (length(category_absent)> 0){
          print(paste0("Varialbe ", name_var," does not have values: ",
                        paste(category_absent,collapse=",")," in the train data."))
        }
        
        logic_left <- paste(paste0("!strcmp (",name_var,',"',category_left,'")'),collapse='||')
        logic_right<- paste(paste0("!strcmp (",name_var,',"',category_right,'")'),collapse='||')
 
        GBM_Scoring <- paste0(GBM_Scoring," if (",logic_left,") {node = ",
                              as.character(scoring_matrix[i_nodes,'LeftNode']),";\n} else if (",
                              logic_right,") {node = ", 
                              as.character(scoring_matrix[i_nodes,'RightNode']),
                              ";\n} else {node = ",as.character(scoring_matrix[i_nodes,'MissingNode']),
                              ";\n} \n break; \n") 
      }
    

    }
    GBM_Scoring <- paste0(GBM_Scoring,"};\n")
  }
   GBM_Scoring <- paste0(GBM_Scoring,"return score;\n}\n")  
  writeLines(GBM_Scoring,file.path(model_location,paste0(model_name,".c"),sep=""))
} else if (language == "sas") {
  
  GBM_Scoring <- paste0("/*gbm(",paste(paste(names(gbm_object$call)[2:length(names(gbm_object$call))],
                                             as.character(gbm_object$call)[2:length(names(gbm_object$call))],
                                             sep="=",collapse=","),sep = "\n"),")*/\n\n")
  
  for (i_var in 1:length(gbm_object$var.names)){
    if (class(gbm_object$var.levels[[i_var]]) == "numeric"){
      GBM_Scoring <- paste0(GBM_Scoring,"/* ",gbm_object$var.names[i_var],
                                   ", datatype: Numeric */\n")
    } else {
      GBM_Scoring <- paste0(GBM_Scoring,"/*",gbm_object$var.names[i_var],
                                   ", datatype: character */\n")      
    }
    
  }
  if (is.null(missing_value)){
    GBM_Scoring <- paste0(GBM_Scoring,"\nMISSING = .;\n")
  } else {
    GBM_Scoring <- paste0(GBM_Scoring,"\nMISSING = ",as.character(missing_value),";\n")      
  }
  
  GBM_Scoring <- paste0(GBM_Scoring,"score = 0;\nlink TN_1_N0;\nreturn;\n")
   
  for (i_tree in 1:n_trees){
    scoring_matrix <- pretty.gbm.tree(gbm_object,i_tree)   
    GBM_Scoring <- paste0(GBM_Scoring,
                          "/* Tree ",as.character(i_tree), " */\n")
    GBM_Scoring <- paste0(GBM_Scoring,
                          "/* Total terminal nodes: ",
                          as.character(sum(scoring_matrix$SplitVar == -1)), " */\n")


    for (i_nodes in 1: (nrow(scoring_matrix))){
    
      if (scoring_matrix[i_nodes,'SplitVar'] == -1){
        GBM_Scoring <- paste0(GBM_Scoring,
                              "TN_",as.character(i_tree),"_N",as.character(i_nodes -1),":")
        GBM_Scoring <- paste0(GBM_Scoring,"score += ", 
                              as.character(scoring_matrix[i_nodes,'Prediction']),";\n")
        GBM_Scoring <- paste0(GBM_Scoring,"GOTO ","TN_",as.character(i_tree+1),"_N0",";\n\n")        
        
      } else if (
        class(gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]]) == 'numeric'&&
          names(gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]])[1] == '0%'){
        GBM_Scoring <- paste0(GBM_Scoring,
                              "TN_",as.character(i_tree),"_N",as.character(i_nodes -1),
                              ":\n if ",
                              gbm_object$var.names[scoring_matrix[i_nodes,'SplitVar']+1],
                              "= MISSING then GOTO ","TN_",as.character(i_tree),"_N",
                              as.character(scoring_matrix[i_nodes,'MissingNode']),";\n else if ",
                              gbm_object$var.names[scoring_matrix[i_nodes,'SplitVar']+1],
                              "<= ", as.character(scoring_matrix[i_nodes,'SplitCodePred']),
                              " then GOTO ","TN_",as.character(i_tree),"_N",
                              as.character(scoring_matrix[i_nodes,'LeftNode']),
                              ";\n else GOTO ","TN_",as.character(i_tree),"_N",as.character(scoring_matrix[i_nodes,'RightNode']),
                              ";\n \n  \n") 
      } else if (gbm_object$var.type[scoring_matrix[i_nodes,'SplitVar']+1] == 0){
        name_var <- gbm_object$var.names[scoring_matrix[i_nodes,'SplitVar']+1]
        left_index <- scoring_matrix[i_nodes,'SplitCodePred']
        category_left <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][1:(left_index+0.5)]
        category_right <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][(left_index+1.5):
                                                                                          length(gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]])]
        
        logic_left <- paste(name_var," in (",paste(paste0("'",category_left,"'"),collapse = ","),")")
        logic_right<- paste(name_var," in (",paste(paste0("'",category_right,"'"),collapse = ","),")")
        
        GBM_Scoring <- paste0(GBM_Scoring,
                              "TN_",as.character(i_tree),"_N",as.character(i_nodes -1),
                              ":\n if ",logic_left," then GOTO ","TN_",as.character(i_tree),"_N",
                              as.character(scoring_matrix[i_nodes,'LeftNode']),";\n else if ",
                              logic_right," then GOTO ","TN_",as.character(i_tree),"_N",
                              as.character(scoring_matrix[i_nodes,'RightNode']),
                              ";\n else GOTO ","TN_",as.character(i_tree),"_N",
                              as.character(scoring_matrix[i_nodes,'MissingNode']),
                              ";\n \n\n")
        
      }  else {
        name_var <- gbm_object$var.names[scoring_matrix[i_nodes,'SplitVar']+1]
        left_index <- gbm_object$c.splits[scoring_matrix[i_nodes,'SplitCodePred'] + 1][[1]]
        category_left <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][left_index==-1]
        category_right <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][left_index==1]
        category_absent <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][left_index==0]
        if (length(category_absent)> 0){
          print(paste0("Varialbe ", name_var," does not have values: ",
                       paste(category_absent,collapse=",")," in the train data."))
        }
        
        logic_left <- paste(name_var," in (",paste(paste0("'",category_left,"'"),collapse = ","),")")
        logic_right<- paste(name_var," in (",paste(paste0("'",category_right,"'"),collapse = ","),")")
        
        GBM_Scoring <- paste0(GBM_Scoring,
                              "TN_",as.character(i_tree),"_N",as.character(i_nodes),
                              ":\n if ",logic_left," then GOTO ","TN_",as.character(i_tree),"_N",
                              as.character(scoring_matrix[i_nodes,'LeftNode']),";\n else if ",
                              logic_right," then GOTO ","TN_",as.character(i_tree),"_N",
                              as.character(scoring_matrix[i_nodes,'RightNode']),
                              ";\n else GOTO ","TN_",as.character(i_tree),"_N",
                              as.character(scoring_matrix[i_nodes,'MissingNode']),
                              ";\n \n\n")
      }
      
      
    }
  }
  GBM_Scoring <- paste0(GBM_Scoring,"\nreturn;\nrun;\n"
  writeLines(GBM_Scoring,file.path(model_location,paste0(model_name,".sas"),sep=""))
}
  else if (language == "java") {
    
    GBM_Scoring <- paste0("/*gbm(",paste(paste(names(gbm_object$call)[2:length(names(gbm_object$call))],
                                               as.character(gbm_object$call)[2:length(names(gbm_object$call))],
                                               sep="=",collapse=","),sep = "\n"),")*/\n\n")
    GBM_Scoring <- paste0(GBM_Scoring,"import java.util.*;\n")
    GBM_Scoring <- paste0(GBM_Scoring,"import java.util.Arrays;\n")
    
    GBM_Scoring <- paste0(GBM_Scoring,"public class ",model_name,"{\n\n")
    GBM_Scoring <- paste0(GBM_Scoring,"private static boolean string_contains(String[] str_arr, ",
                          "String str_Value) {\n","for(String s: str_arr){\n",
                          "if(s.equals(str_Value)) return true;","\n}\nreturn false;\n}\n\n")
    
    GBM_Scoring <- paste0(GBM_Scoring,"public double ",model_name,"(");
    
    n_string_array <- 0
    GBM_Scoring_suffix <-''
    
    for (i_var in 1:length(gbm_object$var.names)){
      if (class(gbm_object$var.levels[[i_var]]) == "numeric"){
        GBM_Scoring <- paste0(GBM_Scoring,"double ",gbm_object$var.names[i_var],
                              ifelse(i_var == length(gbm_object$var.names),
                                     "){",",\n"))
      } else {
        GBM_Scoring <- paste0(GBM_Scoring,"String ",gbm_object$var.names[i_var],
                              ifelse(i_var == length(gbm_object$var.names),
                                     "){",",\n"))        
      }
      
    }
    if (is.null(missing_value)){
      GBM_Scoring <- paste0(GBM_Scoring,"\nprivate static final double MISSING = -Double.MAX_VALUE;\n")
    } else {
      GBM_Scoring <- paste0(GBM_Scoring,"\nprivate static final double MISSING = ",as.character(missing_value),";\n")      
    }
    
    GBM_Scoring <- paste0(GBM_Scoring,"double score = 0;\n")
    GBM_Scoring <- paste0(GBM_Scoring,"int done, node;\n")    
    for (i_tree in 1:n_trees){
      scoring_matrix <- pretty.gbm.tree(gbm_object,i_tree)   
      GBM_Scoring <- paste0(GBM_Scoring,
                            "/* Tree ",as.character(i_tree), " */\n")
      GBM_Scoring <- paste0(GBM_Scoring,
                            "/* Total terminal nodes: ",
                            as.character(sum(scoring_matrix$SplitVar == -1)), " */\n")
      GBM_Scoring <- paste0(GBM_Scoring,"done = 0;\n","node = 0;\n")
      GBM_Scoring <- paste0(GBM_Scoring,"while (done == 0) switch (node) {\n")
      for (i_nodes in 1: (nrow(scoring_matrix))){
        GBM_Scoring <- paste0(GBM_Scoring,"case ", as.character(i_nodes - 1),":\n")     
        if (scoring_matrix[i_nodes,'SplitVar'] == -1){
          GBM_Scoring <- paste0(GBM_Scoring,"score += ", 
                                as.character(scoring_matrix[i_nodes,'Prediction']),";\n")
          GBM_Scoring <- paste0(GBM_Scoring,"done = 1;\nbreak;\n")        
          
        } else if (
          class(gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]]) == 'numeric'&&
            names(gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]])[1] == '0%'){
          GBM_Scoring <- paste0(GBM_Scoring," if (",
                                gbm_object$var.names[scoring_matrix[i_nodes,'SplitVar']+1],
                                "== MISSING) {node = ",
                                as.character(scoring_matrix[i_nodes,'MissingNode']),";\n} else if (",
                                gbm_object$var.names[scoring_matrix[i_nodes,'SplitVar']+1],
                                "<= ", as.character(scoring_matrix[i_nodes,'SplitCodePred']),
                                ") {node = ",as.character(scoring_matrix[i_nodes,'LeftNode']),
                                ";\n} else {node = ",as.character(scoring_matrix[i_nodes,'RightNode']),
                                ";\n} \n break; \n") 
        } else if (gbm_object$var.type[scoring_matrix[i_nodes,'SplitVar']+1] == 0){
          name_var <- gbm_object$var.names[scoring_matrix[i_nodes,'SplitVar']+1]
          left_index <- scoring_matrix[i_nodes,'SplitCodePred']
          category_left <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][1:(left_index+0.5)]
          category_right <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][(left_index+1.5):
                                       length(gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]])]
          
          n_string_array <- n_string_array + 1
          logic_left <- paste(paste0('"',category_left,'"'),collapse=',')
          GBM_Scoring_suffix <- paste0(GBM_Scoring_suffix,
                                       "private static final String[] cat_array_",
                                       as.character(n_string_array),"_L = String[] {",
                                       logic_left,"};\n")
          logic_right<- paste(paste0('"',category_right,'"'),collapse=',')
          GBM_Scoring_suffix <- paste0(GBM_Scoring_suffix,
                                       "private static final String[] cat_array_",
                                       as.character(n_string_array),"_R = String[] {",
                                       logic_right,"};\n")
          
          GBM_Scoring <- paste0(GBM_Scoring," if (string_contains(cat_array_",as.character(n_string_array),"_L,",
                                name_var,") {node = ",
                                as.character(scoring_matrix[i_nodes,'LeftNode']),
                                ";\n} else if (string_contains(cat_array_",as.character(n_string_array),"_R,",
                                name_var,") {node = ",
                                as.character(scoring_matrix[i_nodes,'RightNode']),
                                ";\n} else {node = ",as.character(scoring_matrix[i_nodes,'MissingNode']),
                                ";\n} \n break; \n")
          
        }  else {
          name_var <- gbm_object$var.names[scoring_matrix[i_nodes,'SplitVar']+1]
          left_index <- gbm_object$c.splits[scoring_matrix[i_nodes,'SplitCodePred'] + 1][[1]]
          category_left <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][left_index==-1]
          category_right <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][left_index==1]
          category_absent <- gbm_object$var.levels[[scoring_matrix[i_nodes,'SplitVar']+1]][left_index==0]
          if (length(category_absent)> 0){
            print(paste0("Varialbe ", name_var," does not have values: ",
                         paste(category_absent,collapse=",")," in the train data."))
          }
          
          n_string_array <- n_string_array + 1
          logic_left <- paste(paste0('"',category_left,'"'),collapse=',')
          GBM_Scoring_suffix <- paste0(GBM_Scoring_suffix,
                                       "private static final String[] cat_array_",
                                       as.character(n_string_array),"_L = String[] {",
                                       logic_left,"};\n")
          logic_right<- paste(paste0('"',category_right,'"'),collapse=',')
          GBM_Scoring_suffix <- paste0(GBM_Scoring_suffix,
                                       "private static final String[] cat_array_",
                                       as.character(n_string_array),"_R = String[] {",
                                       logic_right,"};\n")
          
          GBM_Scoring <- paste0(GBM_Scoring," if (string_contains(",as.character(n_string_array),"_L,",
                                name_var,") {node = ",
                                as.character(scoring_matrix[i_nodes,'LeftNode']),
                                ";\n} else if (string_contains(",as.character(n_string_array),"_R,",
                                name_var,") {node = ",
                                as.character(scoring_matrix[i_nodes,'RightNode']),
                                ";\n} else {node = ",as.character(scoring_matrix[i_nodes,'MissingNode']),
                                ";\n} \n break; \n")
        }
        
        
      }
      GBM_Scoring <- paste0(GBM_Scoring,"};\n")
    }
    GBM_Scoring <- paste0(GBM_Scoring,"return score;\n}\n\n")
    GBM_Scoring <- paste0(GBM_Scoring, GBM_Scoring_suffix,"}\n")  
    
    writeLines(GBM_Scoring,file.path(model_location,paste0(model_name,".java"),sep=""))
  }
}

