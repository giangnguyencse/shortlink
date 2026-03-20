# Sử dụng bản slim để giảm thiểu dung lượng image, tăng tốc độ pull/deploy
ARG RUBY_VERSION=3.3.0
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base

# Set working directory
WORKDIR /rails

# Set environment variables cho production/staging
ENV RAILS_ENV="development" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="production"

# --- Build Stage ---
FROM base as build

# Cài đặt các thư viện C cần thiết để build gems (pg, etc.)
# Xóa cache của apt ngay sau khi cài để giảm dung lượng image
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy Gemfile trước để tận dụng Docker Layer Caching
# Nếu Gemfile không đổi, Docker sẽ bỏ qua bước bundle install này ở các lần build sau
COPY Gemfile Gemfile.lock* ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy toàn bộ source code vào
COPY . .

# --- Final Stage ---
FROM base

# Cài đặt các thư viện runtime cần thiết (không chứa các tool build nặng nề)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libpq-dev postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts (gems và app code) từ build stage sang
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# SECURITY BOOSTER: Không chạy app bằng quyền root
# Tạo một non-root user tên là 'rails' và phân quyền
# SECURITY BOOSTER: Không chạy app bằng quyền root
# Tạo một non-root user tên là 'rails' và phân quyền
RUN useradd rails --create-home --shell /bin/bash && \
    mkdir -p db log tmp storage && \
    chown -R rails:rails db log tmp storage
USER rails:rails

# Copy entrypoint script để xử lý lỗi "server.pid already exists" kinh điển của Rails
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Expose port
EXPOSE 3000

# Lệnh khởi chạy server mặc định (Puma)
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]