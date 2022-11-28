if [[ ! -d jing-trang ]]; then
  git clone https://github.com/relaxng/jing-trang.git
  cd jing-trang
  ./ant
  cd ..
fi

rm -f relaton-models/grammars/*.rng
git submodule update

cd relaton-models/grammars
git checkout main && git pull
cd ../..
cp relaton-models/grammars/biblio.rnc .

java -jar jing-trang/build/trang.jar -I rnc -O rng biblio.rnc biblio.rng
java -jar jing-trang/build/trang.jar -I rnc -O rng basicdoc.rnc basicdoc.rng
java -jar jing-trang/build/trang.jar -I rnc -O rng basicdoc-compile.rnc basicdoc-compile.rng
