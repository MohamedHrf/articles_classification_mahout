
if [ "$1" = "--help" ] || [ "$1" = "--?" ]; then
  echo "This script runs SGD and Bayes classifiers over the arab artiles."
  exit
fi

SCRIPT_PATH=${0%/*}
if [ "$0" != "$SCRIPT_PATH" ] && [ "$SCRIPT_PATH" != "" ]; then
  cd $SCRIPT_PATH
fi
START_PATH=`pwd`


DFS="hdfs dfs"
DFSRM="hdfs dfs -rm -r -skipTrash"
MAHOUT=/usr/local/mahout/bin/mahout
WORK_DIR=/articles_classification


algorithm=( cnaivebayes-MapReduce naivebayes-MapReduce clean)
if [ -n "$1" ]; then
  choice=$1
else
  echo "Please select a number to choose the corresponding task to run"
  echo "1. ${algorithm[0]}"
  echo "2. ${algorithm[1]}"
  echo "3. ${algorithm[3]}-- cleans up the work area in $WORK_DIR"
  read -p "Enter your choice : " choice
fi

echo "ok. You chose $choice and we'll use ${algorithm[$choice-1]}"
alg=${algorithm[$choice-1]}

if [ "x$alg" != "xclean" ]; then
  echo "creating work directory at ${WORK_DIR}"

  # mkdir -p ${WORK_DIR}
  if [ ! -e ${WORK_DIR}/aricles-bayesinput ]; then
    if [ ! -e /home/hadoop/articles ]; then
      echo "/home/hadoop/articles  n'existe pas"
    fi
  fi
fi
#echo $START_PATH
cd $START_PATH
cd ../..

  set -e

  c=""

  set -x
 
  if [ "$HADOOP_HOME" != "" ] && [ "$MAHOUT_LOCAL" == "" ] ; then
    echo "Copying articles data to HDFS"
    set +e
    $DFSRM ${WORK_DIR}/articles
    $DFS -mkdir -p ${WORK_DIR}
    $DFS -mkdir ${WORK_DIR}/articles
    set -e
 
    echo "Copying articles  data to Hadoop 3 HDFS"
      $DFS -put /home/hadoop/articles ${WORK_DIR}/
  fi

  echo "Creating sequence files from articles  data"
  $MAHOUT seqdirectory \
    -i ${WORK_DIR}/articles \
    -o ${WORK_DIR}/articles-seq -ow

  echo "Converting sequence files to vectors"
  $MAHOUT seq2sparse \
    -i ${WORK_DIR}/articles-seq \
    -o ${WORK_DIR}/articles-vectors  -lnorm -nv  -wt tfidf

  echo "Creating training and holdout set with a random 80-20 split of the generated vector dataset"
  $MAHOUT split \
    -i ${WORK_DIR}/articles-vectors/tfidf-vectors \
    --trainingOutput ${WORK_DIR}/articles-train-vectors \
    --testOutput ${WORK_DIR}/articles-test-vectors  \
    --randomSelectionPct 20 --overwrite --sequenceFiles -xm sequential

    if [ "x$alg" == "xnaivebayes-MapReduce"  -o  "x$alg" == "xcnaivebayes-MapReduce" ]; then

      echo "Training Naive Bayes model"
      $MAHOUT trainnb \
        -i ${WORK_DIR}/articles-train-vectors \
        -o ${WORK_DIR}/model \
        -li ${WORK_DIR}/labelindex \
        -ow $c

      echo "Self testing on training set"

      $MAHOUT testnb \
        -i ${WORK_DIR}/articles-train-vectors\
        -m ${WORK_DIR}/model \
        -l ${WORK_DIR}/labelindex \
        -ow -o ${WORK_DIR}/articles-testing $c

      echo "Testing on holdout set"

      $MAHOUT testnb \
        -i ${WORK_DIR}/articles-test-vectors\
        -m ${WORK_DIR}/model \
        -l ${WORK_DIR}/labelindex \
        -ow -o ${WORK_DIR}/articles-testing $c

elif [ "x$alg" == "xclean" ]; then
  rm -rf $WORK_DIR
  rm -rf /tmp/news-group.model
  $DFSRM $WORK_DIR
fi
# Remove the work directory
#