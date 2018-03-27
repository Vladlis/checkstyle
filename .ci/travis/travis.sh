#!/bin/bash
# Attention, there is no "-x" to avoid problems on Travis
set -e

case $1 in

nondex)
  mvn -e --fail-never clean nondex:nondex -DargLine='-Xms1024m -Xmx2048m'
  cat `grep -RlE 'td class=.x' .nondex/ | cat` < /dev/null > output.txt
  RESULT=$(cat output.txt | wc -c)
  cat output.txt
  echo 'Size of output:'$RESULT
  if [[ $RESULT != 0 ]]; then sleep 5s; false; fi
  ;;

versions)
  if [[ -v TRAVIS_EVENT_TYPE && $TRAVIS_EVENT_TYPE != "cron" ]]; then exit 0; fi
  mvn -e clean versions:dependency-updates-report versions:plugin-updates-report
  if [ $(grep "<nextVersion>" target/*-updates-report.xml | cat | wc -l) -gt 0 ]; then
    echo "Version reports (dependency-updates-report.xml):"
    cat target/dependency-updates-report.xml
    echo "Version reports (plugin-updates-report.xml):"
    cat target/plugin-updates-report.xml
    echo "New dependency versions:"
    grep -B 7 -A 7 "<nextVersion>" target/dependency-updates-report.xml | cat
    echo "New plugin versions:"
    grep -B 4 -A 7 "<nextVersion>" target/plugin-updates-report.xml | cat
    echo "Verification is failed."
    sleep 5s
    false
  else
    echo "No new versions found"
  fi
  ;;

assembly-run-all-jar)
  mvn -e clean package -Passembly
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo version:$CS_POM_VERSION
  java -jar target/checkstyle-$CS_POM_VERSION-all.jar -c /google_checks.xml \
        src/it/resources/com/google/checkstyle/test/chapter3filestructure/rule332nolinewrap/InputNoLineWrapGood.java > output.log
  if grep -vE '(Starting audit)|(warning)|(Audit done.)' output.log ; then exit 1; fi
  if grep 'warning' output.log ; then exit 1; fi
  ;;

sonarqube)
  # token could be generated at https://sonarcloud.io/account/security/
  # executon on local: SONAR_TOKEN=xxxxxxxxxx ./.ci/travis/travis.sh sonarqube
  if [[ -v TRAVIS_PULL_REQUEST && $TRAVIS_PULL_REQUEST && $TRAVIS_PULL_REQUEST =~ ^([0-9]*)$ ]]; then exit 0; fi
  if [[ -z $SONAR_TOKEN ]]; then echo "SONAR_TOKEN is not set"; sleep 5s; exit 1; fi
  export MAVEN_OPTS='-Xmx2000m'
  mvn -e clean package sonar:sonar \
       -Dsonar.host.url=https://sonarcloud.io \
       -Dsonar.login=$SONAR_TOKEN \
       -Dmaven.test.failure.ignore=true \
       -Dcheckstyle.skip=true -Dpmd.skip=true -Dcheckstyle.ant.skip=true
  ;;

release-dry-run)
  if [ $(git log -1 | grep -E "\[maven-release-plugin\] prepare release" | cat | wc -l) -lt 1 ]; then
    mvn -e release:prepare -DdryRun=true --batch-mode -Darguments='-DskipTests -DskipITs \
      -Djacoco.skip=true -Dpmd.skip=true -Dspotbugs.skip=true -Dxml.skip=true \
      -Dcheckstyle.ant.skip=true -Dcheckstyle.skip=true -Dgpg.skip=true'
  fi
  ;;

releasenotes-gen)
  .ci/travis/xtr_releasenotes-gen.sh
  ;;

pr-description)
  .ci/travis/xtr_pr-description.sh
  ;;

check-chmod)
  .ci/travis/checkchmod.sh
  ;;

all-sevntu-checks)
  xmlstarlet sel --net --template -m .//module -v "@name" -n config/checkstyle_sevntu_checks.xml \
    | grep -vE "Checker|TreeWalker|Filter|Holder" | grep -v "^$" \
    | sed "s/com\.github\.sevntu\.checkstyle\.checks\..*\.//" \
    | sort | uniq | sed "s/Check$//" > file.txt
  wget -q http://sevntu-checkstyle.github.io/sevntu.checkstyle/apidocs/allclasses-frame.html -O - \
    | grep "<li>" | cut -d '>' -f 3 | sed "s/<\/a//" \
    | grep -E "Check$" \
    | sort | uniq | sed "s/Check$//" > web.txt
  diff -u web.txt file.txt
  ;;

no-error-test-sbe)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo version:$CS_POM_VERSION
  mvn -e clean install -Pno-validations
  git clone https://github.com/real-logic/simple-binary-encoding.git
  cd simple-binary-encoding
  git checkout 963814f8ca1456de9daaf67e78663e7d877871a9
  sed -i'' "s/'com.puppycrawl.tools:checkstyle:.*'/'com.puppycrawl.tools:checkstyle:$CS_POM_VERSION'/" build.gradle
  ./gradlew build
  ;;

no-exception-test-checkstyle-sevntu-checkstyle)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo CS_version: $CS_POM_VERSION
  git clone https://github.com/checkstyle/contribution
  cd contribution/checkstyle-tester
  sed -i.'' 's/^guava/#guava/' projects-to-test-on.properties
  sed -i.'' 's/#checkstyle/checkstyle/' projects-to-test-on.properties
  sed -i.'' 's/#sevntu-checkstyle/sevntu-checkstyle/' projects-to-test-on.properties
  cd ../../
  mvn -e clean install -Pno-validations
  cd contribution/checkstyle-tester
  export MAVEN_OPTS="-Xmx2048m"
  groovy ./launch.groovy --listOfProjects projects-to-test-on.properties --config checks-nonjavadoc-error.xml --checkstyleVersion $CS_POM_VERSION
  ;;

no-exception-test-guava)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo CS_version: $CS_POM_VERSION
  git clone https://github.com/checkstyle/contribution
  cd contribution/checkstyle-tester
  sed -i.'' 's/^guava/#guava/' projects-to-test-on.properties
  sed -i.'' 's/#guava|/guava|/' projects-to-test-on.properties
  cd ../../
  mvn -e clean install -Pno-validations
  cd contribution/checkstyle-tester
  export MAVEN_OPTS="-Xmx2048m"
  groovy ./launch.groovy --listOfProjects projects-to-test-on.properties --config checks-nonjavadoc-error.xml --checkstyleVersion $CS_POM_VERSION
  ;;

no-exception-test-guava-with-google-checks)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo CS_version: $CS_POM_VERSION
  git clone https://github.com/checkstyle/contribution
  cd contribution/checkstyle-tester
  sed -i.'' 's/^guava/#guava/' projects-to-test-on.properties
  sed -i.'' 's/#guava|/guava|/' projects-to-test-on.properties
  cd ../../
  mvn -e clean install -Pno-validations
  sed -i.'' 's/warning/ignore/' src/main/resources/google_checks.xml
  cd contribution/checkstyle-tester
  export MAVEN_OPTS="-Xmx2048m"
  groovy ./launch.groovy --listOfProjects projects-to-test-on.properties --config ../../src/main/resources/google_checks.xml --checkstyleVersion $CS_POM_VERSION
  ;;

no-exception-test-hibernate)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo CS_version: $CS_POM_VERSION
  git clone https://github.com/checkstyle/contribution
  cd contribution/checkstyle-tester
  sed -i.'' 's/^guava/#guava/' projects-to-test-on.properties
  sed -i.'' 's/#hibernate-orm/hibernate-orm/' projects-to-test-on.properties
  cd ../../
  mvn -e clean install -Pno-validations
  cd contribution/checkstyle-tester
  export MAVEN_OPTS="-Xmx2048m"
  groovy ./launch.groovy --listOfProjects projects-to-test-on.properties --config checks-nonjavadoc-error.xml --checkstyleVersion $CS_POM_VERSION
  ;;

no-exception-test-spotbugs)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo CS_version: $CS_POM_VERSION
  git clone https://github.com/checkstyle/contribution
  cd contribution/checkstyle-tester
  sed -i.'' 's/^guava/#guava/' projects-to-test-on.properties
  sed -i.'' 's/#spotbugs/spotbugs/' projects-to-test-on.properties
  cd ../../
  mvn -e clean install -Pno-validations
  cd contribution/checkstyle-tester
  export MAVEN_OPTS="-Xmx2048m"
  groovy ./launch.groovy --listOfProjects projects-to-test-on.properties --config checks-nonjavadoc-error.xml --checkstyleVersion $CS_POM_VERSION
  ;;

no-exception-test-spring-framework)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo CS_version: $CS_POM_VERSION
  git clone https://github.com/checkstyle/contribution
  cd contribution/checkstyle-tester
  sed -i.'' 's/^guava/#guava/' projects-to-test-on.properties
  sed -i.'' 's/#spring-framework/spring-framework/' projects-to-test-on.properties
  cd ../../
  mvn -e clean install -Pno-validations
  cd contribution/checkstyle-tester
  export MAVEN_OPTS="-Xmx2048m"
  groovy ./launch.groovy --listOfProjects projects-to-test-on.properties --config checks-nonjavadoc-error.xml --checkstyleVersion $CS_POM_VERSION
  ;;

no-exception-test-hbase)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo CS_version: $CS_POM_VERSION
  git clone https://github.com/checkstyle/contribution
  cd contribution/checkstyle-tester
  sed -i.'' 's/^guava/#guava/' projects-to-test-on.properties
  sed -i.'' 's/#Hbase/Hbase/' projects-to-test-on.properties
  cd ../../
  mvn -e clean install -Pno-validations
  cd contribution/checkstyle-tester
  export MAVEN_OPTS="-Xmx2048m"
  groovy ./launch.groovy --listOfProjects projects-to-test-on.properties --config checks-nonjavadoc-error.xml --checkstyleVersion $CS_POM_VERSION
  ;;

no-exception-test-Pmd-elasticsearch-lombok-ast)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo CS_version: $CS_POM_VERSION
  git clone https://github.com/checkstyle/contribution
  cd contribution/checkstyle-tester
  sed -i.'' 's/^guava/#guava/' projects-to-test-on.properties
  sed -i.'' 's/#pmd/pmd/' projects-to-test-on.properties
  sed -i.'' 's/#elasticsearch/elasticsearch/' projects-to-test-on.properties
  sed -i.'' 's/#lombok-ast/lombok-ast/' projects-to-test-on.properties
  cd ../../
  mvn -e clean install -Pno-validations
  cd contribution/checkstyle-tester
  export MAVEN_OPTS="-Xmx2048m"
  groovy ./launch.groovy --listOfProjects projects-to-test-on.properties --config checks-nonjavadoc-error.xml --checkstyleVersion $CS_POM_VERSION
  ;;

no-exception-test-alot-of-project1)
  CS_POM_VERSION=$(mvn -e -q -Dexec.executable='echo' -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo CS_version: $CS_POM_VERSION
  git clone https://github.com/checkstyle/contribution
  cd contribution/checkstyle-tester
  sed -i.'' 's/^guava/#guava/' projects-to-test-on.properties
  sed -i.'' 's/#RxJava/RxJava/' projects-to-test-on.properties
  sed -i.'' 's/#java-design-patterns/java-design-patterns/' projects-to-test-on.properties
  sed -i.'' 's/#MaterialDesignLibrary/MaterialDesignLibrary/' projects-to-test-on.properties
  sed -i.'' 's/#apache-ant/apache-ant/' projects-to-test-on.properties
  sed -i.'' 's/#apache-jsecurity/apache-jsecurity/' projects-to-test-on.properties
  sed -i.'' 's/#android-launcher/android-launcher/' projects-to-test-on.properties
  cd ../../
  mvn -e clean install -Pno-validations
  cd contribution/checkstyle-tester
  export MAVEN_OPTS="-Xmx2048m"
  groovy ./launch.groovy --listOfProjects projects-to-test-on.properties --config checks-nonjavadoc-error.xml --checkstyleVersion $CS_POM_VERSION
  ;;

*)
  echo "Unexpected argument: $1"
  sleep 5s
  false
  ;;

esac
