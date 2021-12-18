# Sigbus Factor - _Personal Blog_

A small, minimal personal tech blog deployed to GitHub pages using the Jekyll
Minima theme. We intend to make this site as simple as reasonable in order to
lower the barrier for maintenance and writing posts.


## Testing the Site

We use `docker-compose` or `podman-compose` and the `jekyll/jekyll` image for
running test builds and serving the website during the testing phase, and rely
on GitHub for building and deploying to "production". Substitute
`docker-compose` for `podman-compose` anywhere suitable; the commands should
still work.

To spin up the test server, in the repository's root directory, run:
```shell
docker-compose up
```
The server should now be exposed on port 4000 for local browsing. You may need
super-user privileges for this depending on what flavor of Docker you are using.

Run the following to stop and remove the web server container:
```shell
docker-compose down
```

## Updating Ruby Packages

```shell
# Substitute $CONTAINER_NAME as appropriate
docker-compose exec $CONTAINER_NAME bash -c 'bundle update && bundle lock'
```


## Adding New posts

Pretty straightforward: Just add a new post markdown file to `_posts/`.


## References

 * [Jekyll Docker image](https://hub.docker.com/jekyll/jekyll)
 * [Jekyll Minima theme](https://jekyll.github.io/minima)
