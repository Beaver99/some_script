param (
    [string]$m
)
git add .
git commit -m $m
git push -u origin master